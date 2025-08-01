require 'json'
require 'yaml'
require 'logger'
require 'pathname'
require 'uri'
require_relative 'models'

# Placeholder modules/classes; replace with your actual implementations.
# module Utcp
#   class ClientTransportInterface; end
# end
# class TextProvider; attr_reader :file_path, :name; end
# class OpenApiConverter
#   def initialize(spec, spec_url:, provider_name:); end
#   def convert; end
# end
# class UtcpManual
#   attr_reader :tools
#   def initialize(**kwargs); end
# end

class TextTransport
  # Transport implementation for text file-based tool providers.
  # Reads tool definitions from local text or YAML files.
  # Since tools are static, tool calls beyond reading the file are not supported.
  def initialize(base_path: nil)
    @base_path = base_path
    @logger = Logger.new($stdout)
    @logger.progname = 'TextTransport'
  end

  def register_tool_provider(manual_provider)
    unless manual_provider.is_a?(TextProvider)
      raise ArgumentError, "TextTransport can only be used with TextProvider"
    end

    file_path = Pathname.new(manual_provider.file_path)
    if !file_path.absolute? && @base_path
      file_path = Pathname.new(@base_path) + file_path
    end

    log_info("Reading tool definitions from '#{file_path}'")

    begin
      unless file_path.exist?
        raise Errno::ENOENT, "Tool definition file not found: #{file_path}"
      end

      raw_content = file_path.read(encoding: 'utf-8')

      data =
        if ['.yaml', '.yml'].include?(file_path.extname.downcase)
          YAML.safe_load(raw_content)
        else
          JSON.parse(raw_content)
        end

      utcp_manual = nil

      if data.is_a?(Hash) && data.key?('version') && data.key?('tools')
        log_info("Detected UTCP manual in '#{file_path}'.")
        # Assuming UtcpManual accepts keyword args from the hash
        utcp_manual = UtcpManual.new(**symbolize_keys_recursive(data))
      elsif data.is_a?(Hash) && (data.key?('openapi') || data.key?('swagger') || data.key?('paths'))
        log_info("Assuming OpenAPI spec in '#{file_path}'. Converting to UTCP manual.")
        spec_url = file_path.realpath.to_uri
        converter = OpenApiConverter.new(data, spec_url: spec_url, provider_name: manual_provider.name)
        utcp_manual = converter.convert
      else
        raise ArgumentError, "File '#{file_path}' is not a valid OpenAPI specification or UTCP manual"
      end

      tools = utcp_manual.tools
      log_info("Successfully loaded #{tools.size} tools from '#{file_path}'")
      tools
    rescue Errno::ENOENT => e
      log_error("Tool definition file not found: #{file_path}")
      raise
    rescue JSON::ParserError, Psych::SyntaxError => e
      log_error("Failed to parse file '#{file_path}': #{e.message}")
      raise
    rescue => e
      log_error("Unexpected error reading file '#{file_path}': #{e.message}")
      []
    end
  end

  def deregister_tool_provider(manual_provider)
    if manual_provider.is_a?(TextProvider)
      log_info("Deregistering text provider '#{manual_provider.name}' (no-op)")
    end
    # No-op otherwise
    nil
  end

  def call_tool(tool_name, arguments, tool_provider)
    unless tool_provider.is_a?(TextProvider)
      raise ArgumentError, "TextTransport can only be used with TextProvider"
    end

    file_path = Pathname.new(tool_provider.file_path)
    if !file_path.absolute? && @base_path
      file_path = Pathname.new(@base_path) + file_path
    end

    log_info("Reading content from '#{file_path}' for tool '#{tool_name}'")

    begin
      unless file_path.exist?
        raise Errno::ENOENT, "File not found: #{file_path}"
      end

      content = file_path.read(encoding: 'utf-8')
      log_info("Successfully read #{content.length} characters from '#{file_path}'")
      content
    rescue Errno::ENOENT => e
      log_error("File not found: #{file_path}")
      raise
    rescue => e
      log_error("Error reading file '#{file_path}': #{e.message}")
      raise
    end
  end

  def close
    log_info("Closing text transport (no-op)")
    nil
  end

  private

  def log_info(message)
    @logger.info(message)
  end

  def log_error(message)
    @logger.error(message)
  end

  # Recursively converts string keys in hashes to symbols, preserving structure.
  def symbolize_keys_recursive(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), acc|
        key = k.respond_to?(:to_sym) ? k.to_sym : k
        acc[key] = symbolize_keys_recursive(v)
      end
    when Array
      obj.map { |e| symbolize_keys_recursive(e) }
    else
      obj
    end
  end
end
