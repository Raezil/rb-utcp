# frozen_string_literal: true

require 'open3'
require 'json'
require 'timeout'
require 'logger'
require 'shellwords'
require 'rbconfig'
require_relative 'models'

# Assumes Provider, CliProvider, Tool, and UtcpManual are defined elsewhere, e.g.:
# class CliProvider; attr_accessor :name, :command_name, :env_vars, :working_dir; end
# class Tool; end
# class UtcpManual
#   attr_reader :tools
#   def initialize(**kwargs); ...; end
# end

# Example usage:
#   provider = CliProvider.new(name: 'example', command_name: 'echo')
#   transport = CliTransport.new
#   transport.register_tool_provider(provider)
#   result = transport.call_tool('echo', { message: 'hi' }, provider)

class CliTransport
  DEFAULT_DISCOVERY_TIMEOUT = 30
  DEFAULT_TOOL_TIMEOUT = 60

  def initialize(logger: nil)
    @logger = logger || Logger.new($stdout)
  end

  def register_tool_provider(manual_provider)
    unless manual_provider.is_a?(CliProvider)
      raise ArgumentError, 'CliTransport can only be used with CliProvider'
    end

    if manual_provider.command_name.nil? || manual_provider.command_name.strip.empty?
      raise ArgumentError, "CliProvider '#{manual_provider.name}' must have command_name set"
    end

    log_info("Registering CLI provider '#{manual_provider.name}' with command '#{manual_provider.command_name}'")

    begin
      env = prepare_environment(manual_provider)
      command = split_command(manual_provider.command_name)

      log_info("Executing command for tool discovery: #{command.join(' ')}")

      stdout, stderr, status = execute_command(
        command,
        env: env,
        timeout: DEFAULT_DISCOVERY_TIMEOUT,
        working_dir: manual_provider.working_dir
      )

      output = status.success? ? stdout : stderr

      if output.to_s.strip.empty?
        log_info("No output from command '#{manual_provider.command_name}'")
        return []
      end

      tools = extract_utcp_manual_from_output(output, manual_provider.name)
      log_info("Discovered #{tools.size} tools from CLI provider '#{manual_provider.name}'")
      tools
    rescue StandardError => e
      log_error("Error discovering tools from CLI provider '#{manual_provider.name}': #{e}")
      []
    end
  end

  def deregister_tool_provider(manual_provider)
    if manual_provider.is_a?(CliProvider)
      log_info("Deregistering CLI provider '#{manual_provider.name}' (no-op)")
    end
  end

  def call_tool(tool_name, arguments, tool_provider)
    unless tool_provider.is_a?(CliProvider)
      raise ArgumentError, 'CliTransport can only be used with CliProvider'
    end

    if tool_provider.command_name.nil? || tool_provider.command_name.strip.empty?
      raise ArgumentError, "CliProvider '#{tool_provider.name}' must have command_name set"
    end

    command = split_command(tool_provider.command_name)
    if arguments && !arguments.empty?
      command.concat(format_arguments(arguments))
    end

    log_info("Executing CLI tool '#{tool_name}': #{command.join(' ')}")

    begin
      env = prepare_environment(tool_provider)
      stdout, stderr, status = execute_command(
        command,
        env: env,
        timeout: DEFAULT_TOOL_TIMEOUT,
        working_dir: tool_provider.working_dir
      )

      output = status.success? ? stdout : stderr
      if status.success?
        log_info("CLI tool '#{tool_name}' executed successfully (exit code 0)")
      else
        log_info("CLI tool '#{tool_name}' exited with code #{status.exitstatus}, returning stderr")
      end

      if output.to_s.strip.empty?
        log_info("CLI tool '#{tool_name}' produced no output")
        return ''
      end

      begin
        result = JSON.parse(output)
        log_info("Returning JSON output from CLI tool '#{tool_name}'")
        result
      rescue JSON::ParserError
        log_info("Returning text output from CLI tool '#{tool_name}'")
        output.strip
      end
    rescue StandardError => e
      log_error("Error executing CLI tool '#{tool_name}': #{e}")
      raise
    end
  end

  def close
    log_info('Closing CLI transport (no-op)')
  end

  private

  def log_info(message)
    @logger.respond_to?(:info) ? @logger.info("[CliTransport] #{message}") : @logger.call("[CliTransport] #{message}")
  end

  def log_error(message)
    if @logger.respond_to?(:error)
      @logger.error("[CliTransport Error] #{message}")
    else
      @logger.call("[CliTransport Error] #{message}")
    end
  end

  def prepare_environment(provider)
    env = ENV.to_h.dup
    if provider.respond_to?(:env_vars) && provider.env_vars
      env.merge!(provider.env_vars)
    end
    env
  end

  def split_command(cmd_str)
    # On Windows use posix=false equivalent via Shellwords is always POSIX, so be cautious.
    # For most usages, Shellwords.split works; if Windows-specific parsing needed, adjust here.
    Shellwords.split(cmd_str)
  end

  def format_arguments(arguments)
    args = []
    arguments.each do |key, value|
      flag = "--#{key}"
      case value
      when TrueClass
        args << flag
      when FalseClass, NilClass
        # skip
      when Array
        value.each do |item|
          args << flag
          args << item.to_s
        end
      else
        args << flag
        args << value.to_s
      end
    end
    args
  end

  def execute_command(command, env:, timeout:, working_dir: nil)
    stdout_str = ''
    stderr_str = ''
    status = nil

    Timeout.timeout(timeout) do
      Dir.chdir(working_dir) if working_dir
      stdout_str, stderr_str, status = Open3.capture3(env, *command)
    end

    [stdout_str, stderr_str, status]
  rescue Timeout::Error
    log_error("Command timed out after #{timeout} seconds: #{command.join(' ')}")
    # Attempt to kill lingering process is non-trivial with capture3; rely on subprocess termination
    raise
  rescue StandardError => e
    log_error("Error executing command #{command.join(' ')}: #{e}")
    raise
  end

  def extract_utcp_manual_from_output(output, provider_name)
    tools = []

    stripped = output.strip
    if !stripped.empty?
      begin
        data = JSON.parse(stripped)
        tools = parse_tool_data(data, provider_name)
        return tools unless tools.empty?
      rescue JSON::ParserError
        # proceed to line-by-line
      end
    end

    output.each_line do |line|
      line = line.strip
      next unless line.start_with?('{') && line.end_with?('}')

      begin
        data = JSON.parse(line)
        found_tools = parse_tool_data(data, provider_name)
        tools.concat(found_tools)
      rescue JSON::ParserError
        next
      end
    end

    tools
  end

  def parse_tool_data(data, provider_name)
    if data.is_a?(Hash)
      if data.key?('tools')
        begin
          utcp_manual = UtcpManual.model_validate(data)
          return utcp_manual.tools || []
        rescue StandardError => e
          log_error("Invalid UTCP manual format from provider '#{provider_name}': #{e}")
          return []
        end
      elsif data.key?('name') && data.key?('description')
        begin
          return [Tool.model_validate(data)]
        rescue StandardError => e
          log_error("Invalid tool definition from provider '#{provider_name}': #{e}")
          return []
        end
      end
    elsif data.is_a?(Array)
      begin
        return data.map { |tool_data| Tool.model_validate(tool_data) }
      rescue StandardError => e
        log_error("Invalid tool array from provider '#{provider_name}': #{e}")
        return []
      end
    end

    []
  end
end
