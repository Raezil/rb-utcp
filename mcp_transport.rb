require 'async'
require 'json'
require 'logger'
require 'faraday'
require 'base64'
require 'net/http'
require 'uri'
require_relative 'models'

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

  # Helper to fetch from hash with indifferent access (symbol/string)
  def fetch_key(hash, key)
    return nil unless hash
    hash[key] || hash[key.to_s]
  end
  private :fetch_key

  # Internal: list tools via a fresh session
  def list_tools_with_session(server_config, auth: nil)
    transport = fetch_key(server_config, :transport)

    case transport
    when 'http'
      headers = {}
      if auth && auth.is_a?(OAuth2Auth)
        token = handle_oauth2(auth)
        headers['Authorization'] = "Bearer #{token}"
      end

      url = fetch_key(server_config, :url)
      raise ArgumentError, "Missing URL in server config" unless url

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }

      response = http.request(req)
      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP error when listing tools: #{response.code} #{response.body}"
      end
      data = JSON.parse(response.body)
      manual = UtcpManual.model_validate(data)
      manual.tools
    when 'stdio'
      raise ArgumentError, 'stdio transport not implemented'
    else
      raise ArgumentError, "Unsupported MCP transport: #{transport.inspect}"
    end
  end

  # Internal: call tool via a fresh session
  def call_tool_with_session(server_config, tool_name, inputs, auth: nil)
    transport = fetch_key(server_config, :transport)

    case transport
    when 'http'
      headers = { 'Content-Type' => 'application/json' }
      if auth && auth.is_a?(OAuth2Auth)
        token = handle_oauth2(auth)
        headers['Authorization'] = "Bearer #{token}"
      end

      url = fetch_key(server_config, :url)
      raise ArgumentError, "Missing URL in server config" unless url

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      req = Net::HTTP::Post.new(uri, headers)
      # Some MCP endpoints expect tool name in path or body; assume body here
      body_payload = inputs ? inputs.dup : {}
      body_payload['tool'] = tool_name
      req.body = JSON.generate(body_payload)

      response = http.request(req)
      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP error when calling tool '#{tool_name}': #{response.code} #{response.body}"
      end

      JSON.parse(response.body)
    when 'stdio'
      raise ArgumentError, 'stdio transport not implemented'
    else
      raise ArgumentError, "Unsupported MCP transport: #{transport.inspect}"
    end
  end

  # Public: register provider and discover tools
  def register_tool_provider(manual_provider)
    all_tools = []
    if manual_provider.config
      servers = fetch_key(manual_provider.config, :mcpServers)
      if servers
        servers.each do |server_name, server_config|
          begin
            log("Discovering tools for server '#{server_name}' via #{fetch_key(server_config, :transport)}")
            tools = list_tools_with_session(server_config, auth: manual_provider.auth)
            log("Discovered #{tools.size} tools for server '#{server_name}'")
            all_tools.concat(tools)
          rescue => e
            log("Failed to discover tools for server '#{server_name}': #{e}", error: true)
          end
        end
      end
    end
    all_tools
  end

  # Public: call a named tool via provider config
  def call_tool(tool_name, inputs, tool_provider)
    servers = nil
    if tool_provider.config
      servers = fetch_key(tool_provider.config, :mcpServers)
    end
    unless servers
      raise ArgumentError, "No server configuration found for tool '#{tool_name}'"
    end

    normalized_requested = normalize_tool_name(tool_name)

    servers.each do |server_name, server_config|
      begin
        log("Attempting to call tool '#{tool_name}' on server '#{server_name}'")

        tools = list_tools_with_session(server_config, auth: tool_provider.auth)
        tool_names = tools.map { |t| t.name }

        # Accept exact match, suffix match (e.g., "provider.echo" vs "echo"), or last segment
        matched_name = find_matching_tool_name(normalized_requested, tool_names)
        unless matched_name
          log("Tool '#{tool_name}' not found in server '#{server_name}' (available: #{tool_names.join(', ')})")
          next
        end

        resolved_tool_name = matched_name
        result = call_tool_with_session(server_config, resolved_tool_name, inputs, auth: tool_provider.auth)
        return _process_tool_result(result, resolved_tool_name)
      rescue => e
        log("Error calling tool '#{tool_name}' on server '#{server_name}': #{e}", error: true)
        next
      end
    end

    raise ArgumentError, "Tool '#{tool_name}' not found in any configured server"
  end

  # normalize e.g. "mcpdemo.echo" -> ["mcpdemo.echo", "echo"]
  def normalize_tool_name(name)
    return [] if name.nil?
    parts = name.to_s.split('.')
    variants = [name.to_s]
    variants << parts.last if parts.size > 1
    variants
  end
  private :normalize_tool_name

  def find_matching_tool_name(requested_variants, available_names)
    requested_variants.each do |variant|
      return variant if available_names.include?(variant)
    end
    # case-insensitive fallback
    available_names.find { |n| requested_variants.any? { |v| v.casecmp(n).zero? } }
  end
  private :find_matching_tool_name

  def _process_tool_result(result, tool_name)
    log("Processing tool result for '#{tool_name}', raw result class: #{result.class}")

    # If it's a hash with known structured keys, prioritize those.
    if result.is_a?(Hash)
      if result.key?('structured_output') && !result['structured_output'].nil?
        log("Found structured_output in hash result")
        return result['structured_output']
      end

      if result.key?('content')
        content = result['content']
        case content
        when Array
          return content.map { |item| extract_textish(item) }
        else
          return extract_textish(content)
        end
      end

      if result.key?('result')
        return result['result']
      end

      return result
    end

    # Fallback: scalar or other
    extract_textish(result)
  end
  private :_process_tool_result

  def extract_textish(obj)
    return obj if obj.nil?

    if obj.is_a?(String)
      stripped = obj.strip
      # Try parse JSON
      if (stripped.start_with?('{') && stripped.end_with?('}')) ||
         (stripped.start_with?('[') && stripped.end_with?(']'))
        begin
          return JSON.parse(stripped)
        rescue JSON::ParserError
          # fall through
        end
      end

      if stripped.match?(/\A-?\d+\z/)
        return stripped.to_i
      end

      if stripped.match?(/\A-?\d+\.\d+\z/)
        return stripped.to_f
      end

      return stripped
    end

    obj
  end
  private :extract_textish

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
