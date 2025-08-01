require 'async'
require 'json'
require 'logger'
require 'faraday'
require 'base64'
require_relative 'models'

# Placeholder classes/modules: you need real equivalents or adapters in your codebase.
# class StdioServerParameters; end
# def stdio_client(params); end
# def streamablehttp_client(url:, auth:); end
# class ClientSession; end
# class MCPProvider; end
# class OAuth2Auth; end

class MCPTransport
  def initialize(logger: nil)
    @oauth_tokens = {} # client_id => token hash
    @logger = logger || Logger.new($stdout)
  end

  def log(message, error: false)
    if error
      @logger.error("[MCPTransport Error] #{message}")
    else
      @logger.info("[MCPTransport Info] #{message}")
    end
  end

  # Internal: list tools via a fresh session
  def list_tools_with_session(server_config, auth: nil)
    Async do
      case server_config.transport
      when 'stdio'
        params = StdioServerParameters.new(
          command: server_config.command,
          args: server_config.args,
          env: server_config.env
        )
        Async::Task.current.perform do
          stdio_client(params) do |read, write|
            session = ClientSession.new(read, write)
            session.initialize
            tools_response = session.list_tools
            return tools_response.tools
          end
        end
      when 'http'
        auth_header = nil
        if auth && auth.is_a?(OAuth2Auth)
          token = handle_oauth2(auth)
          auth_header = { 'Authorization' => "Bearer #{token}" }
        end

        Async::Task.current.perform do
          streamablehttp_client(url: server_config.url, auth: auth_header) do |read, write, _|
            session = ClientSession.new(read, write)
            session.initialize
            tools_response = session.list_tools
            return tools_response.tools
          end
        end
      else
        raise ArgumentError, "Unsupported MCP transport: #{server_config.transport}"
      end
    end
  end

  # Internal: call tool via a fresh session
  def call_tool_with_session(server_config, tool_name, inputs, auth: nil)
    Async do
      case server_config.transport
      when 'stdio'
        params = StdioServerParameters.new(
          command: server_config.command,
          args: server_config.args,
          env: server_config.env
        )
        Async::Task.current.perform do
          stdio_client(params) do |read, write|
            session = ClientSession.new(read, write)
            session.initialize
            result = session.call_tool(tool_name, arguments: inputs)
            return result
          end
        end
      when 'http'
        auth_header = nil
        if auth && auth.is_a?(OAuth2Auth)
          token = handle_oauth2(auth)
          auth_header = { 'Authorization' => "Bearer #{token}" }
        end

        Async::Task.current.perform do
          streamablehttp_client(url: server_config.url, auth: auth_header) do |read, write, _|
            session = ClientSession.new(read, write)
            session.initialize
            result = session.call_tool(tool_name, arguments: inputs)
            return result
          end
        end
      else
        raise ArgumentError, "Unsupported MCP transport: #{server_config.transport}"
      end
    end
  end

  # Public: register provider and discover tools
  def register_tool_provider(manual_provider)
    all_tools = []
    if manual_provider.config && manual_provider.config.mcpServers
      manual_provider.config.mcpServers.each do |server_name, server_config|
        begin
          log("Discovering tools for server '#{server_name}' via #{server_config.transport}")
          tools_task = list_tools_with_session(server_config, auth: manual_provider.auth)
          tools = tools_task.is_a?(Async::Task) ? tools_task.wait : tools_task
          log("Discovered #{tools.size} tools for server '#{server_name}'")
          all_tools.concat(tools)
        rescue => e
          log("Failed to discover tools for server '#{server_name}': #{e}", error: true)
        end
      end
    end
    all_tools
  end

  # Public: call a named tool via provider config
  def call_tool(tool_name, inputs, tool_provider)
    unless tool_provider.config && tool_provider.config.mcpServers
      raise ArgumentError, "No server configuration found for tool '#{tool_name}'"
    end

    tool_provider.config.mcpServers.each do |server_name, server_config|
      begin
        log("Attempting to call tool '#{tool_name}' on server '#{server_name}'")

        tools_task = list_tools_with_session(server_config, auth: tool_provider.auth)
        tools = tools_task.is_a?(Async::Task) ? tools_task.wait : tools_task
        tool_names = tools.map(&:name)

        unless tool_names.include?(tool_name)
          log("Tool '#{tool_name}' not found in server '#{server_name}'")
          next
        end

        result_task = call_tool_with_session(server_config, tool_name, inputs, auth: tool_provider.auth)
        result = result_task.is_a?(Async::Task) ? result_task.wait : result_task
        return process_tool_result(result, tool_name)
      rescue => e
        log("Error calling tool '#{tool_name}' on server '#{server_name}': #{e}", error: true)
        next
      end
    end

    raise ArgumentError, "Tool '#{tool_name}' not found in any configured server"
  end

  def _process_tool_result(result, tool_name)
    log("Processing tool result for '#{tool_name}', type: #{result.class}")

    if result.respond_to?(:structured_output) && !result.structured_output.nil?
      log("Found structured_output: #{result.structured_output}")
      return result.structured_output
    end

    if result.respond_to?(:content) && !result.content.nil?
      content = result.content
      log("Content type: #{content.class}")

      if content.is_a?(Array)
        log("Content is a list with #{content.size} items")
        return [] if content.empty?

        if content.size == 1
          item = content.first
          if item.respond_to?(:text)
            return parse_text_content(item.text)
          end
          return item
        end

        content.map do |item|
          if item.respond_to?(:text)
            parse_text_content(item.text)
          else
            item
          end
        end
      elsif content.respond_to?(:text)
        return parse_text_content(content.text)
      elsif content.respond_to?(:json)
        return content.json
      else
        return content
      end
    end

    if result.respond_to?(:result)
      return result.result
    end

    result
  end
  private :_process_tool_result

  def parse_text_content(text)
    return text if text.nil? || text.empty?
    stripped = text.strip

    # Try JSON
    if (stripped.start_with?('{') && stripped.end_with?('}')) ||
       (stripped.start_with?('[') && stripped.end_with?(']'))
      begin
        return JSON.parse(stripped)
      rescue JSON::ParserError
        # fall through
      end
    end

    # Try integer
    if stripped.match?(/\A-?\d+\z/)
      return stripped.to_i
    end

    # Try float
    if stripped.match?(/\A-?\d+\.\d+\z/)
      return stripped.to_f
    end

    stripped
  end

  # No-op deregister
  def deregister_tool_provider(manual_provider)
    log("Deregistering provider '#{manual_provider.name}' (no-op in session-per-operation mode)")
    nil
  end

  # OAuth2 client credentials flow with caching
  def handle_oauth2(auth_details)
    client_id = auth_details.client_id

    if @oauth_tokens.key?(client_id)
      return @oauth_tokens[client_id]['access_token']
    end

    # Try Method 1: credentials in body
    begin
      log("Attempting OAuth2 token fetch for '#{client_id}' with credentials in body.")
      conn = Faraday.new(url: auth_details.token_url)
      body = {
        'grant_type' => 'client_credentials',
        'client_id' => client_id,
        'client_secret' => auth_details.client_secret,
        'scope' => auth_details.scope
      }
      response = conn.post('', body)
      if response.status >= 200 && response.status < 300
        token_response = JSON.parse(response.body)
        @oauth_tokens[client_id] = token_response
        return token_response['access_token']
      else
        raise "Status #{response.status}"
      end
    rescue => e
      log("OAuth2 with credentials in body failed: #{e}. Trying Basic Auth header.")
    end

    # Method 2: Basic Auth header
    begin
      log("Attempting OAuth2 token fetch for '#{client_id}' with Basic Auth header.")
      conn = Faraday.new(url: auth_details.token_url) do |f|
        f.request :authorization, :basic, client_id, auth_details.client_secret
      end
      body = {
        'grant_type' => 'client_credentials',
        'scope' => auth_details.scope
      }
      response = conn.post('', body)
      if response.status >= 200 && response.status < 300
        token_response = JSON.parse(response.body)
        @oauth_tokens[client_id] = token_response
        return token_response['access_token']
      else
        raise "Status #{response.status}"
      end
    rescue => e
      log("OAuth2 with Basic Auth header also failed: #{e}", error: true)
      raise e
    end
  end
  private :handle_oauth2

  def close
    log("Closing MCP transport (no-op in session-per-operation mode)")
    nil
  end
end
