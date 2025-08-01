require 'async'
require 'httpx'
require 'json'
require 'uri'
require 'logger'
require_relative 'models'

# Placeholder / expected interfaces; adapt or replace with your actual implementations:
# class ClientTransportInterface; end
# class StreamableHttpProvider; attr_accessor :url, :auth, :headers, :header_fields, :body_field, :content_type, :http_method, :timeout, :chunk_size, :name; end
# class ApiKeyAuth; attr_accessor :api_key, :location, :var_name; end
# class BasicAuth; attr_accessor :username, :password; end
# class OAuth2Auth; attr_accessor :client_id, :client_secret, :token_url, :scope; end
# class UtcpManual; def initialize(**kwargs); end; end

class StreamableHttpClientTransport
  # Client transport implementation for HTTP streaming providers using Async + HTTPX.
  def initialize(logger: nil)
    @oauth_tokens = {} # client_id => token hash
    @log = logger || Logger.new($stdout)
    @active_connections = {} # provider_name => {response: , client: }
  end

  # Apply authentication, returns [auth_header_hash, cookies_hash]
  def apply_auth(provider, headers, query_params)
    auth_header = {}
    cookies = {}

    if provider.auth
      case provider.auth
      when ApiKeyAuth
        if provider.auth.api_key
          case provider.auth.location
          when 'header'
            headers[provider.auth.var_name] = provider.auth.api_key
          when 'query'
            query_params[provider.auth.var_name] = provider.auth.api_key
          when 'cookie'
            cookies[provider.auth.var_name] = provider.auth.api_key
          else
            log_error("Unknown ApiKeyAuth location: #{provider.auth.location}")
          end
        else
          log_error("API key not found for ApiKeyAuth.")
          raise ArgumentError, "API key for ApiKeyAuth not found."
        end
      when BasicAuth
        basic_token = ["#{provider.auth.username}:#{provider.auth.password}"].pack("m0")
        headers['Authorization'] = "Basic #{basic_token}"
      when OAuth2Auth
        # handled separately (async) in caller
      end
    end

    [auth_header, cookies]
  end

  def close
    @log.info("Closing all active HTTP stream connections.")
    @active_connections.dup.each do |provider_name, conn|
      @log.info("Closing connection for provider: #{provider_name}")
      response = conn[:response]
      client = conn[:client]
      # HTTPX responses don't have explicit close; cancel if needed
      # Close underlying connections if applicable
      client&.close if client.respond_to?(:close)
    end
    @active_connections.clear
    @oauth_tokens.clear
  end

  def register_tool_provider(manual_provider)
    unless manual_provider.is_a?(StreamableHttpProvider)
      raise ArgumentError, "StreamableHttpClientTransport can only be used with StreamableHttpProvider"
    end

    url = manual_provider.url

    unless url.start_with?("https://") || url.start_with?("http://localhost") || url.start_with?("http://127.0.0.1")
      raise ArgumentError, "Security error: URL must use HTTPS or localhost to prevent MITM. Got: #{url}"
    end

    @log.info("Discovering tools from '#{manual_provider.name}' (HTTP Stream) at #{url}")

    begin
      request_headers = (manual_provider.headers || {}).dup
      query_params = {}
      auth_header, cookies = apply_auth(manual_provider, request_headers, query_params)

      if manual_provider.auth.is_a?(OAuth2Auth)
        token = await handle_oauth2(manual_provider.auth)
        request_headers['Authorization'] = "Bearer #{token}"
      end

      body_content = nil
      if manual_provider.body_field
        # Discovery usually doesn't send body; placeholder if needed later.
        body_content = nil
      end

      # Prepare request options
      request_opts = {
        headers: request_headers,
        params: query_params,
        cookies: cookies,
        timeout: (manual_provider.timeout ? manual_provider.timeout / 1000.0 : 60.0)
      }

      if body_content
        if request_headers['Content-Type']&.include?('application/json')
          request_opts[:json] = body_content
        else
          request_opts[:content] = body_content
        end
      end

      method = manual_provider.http_method.to_s.downcase.to_sym

      # Use HTTPX in async context
      response = HTTPX.with(timeout: request_opts[:timeout]).request(method, url, headers: request_headers, params: query_params, cookies: cookies, json: request_opts[:json], content: request_opts[:content])
      unless response.status.to_s.start_with?("2")
        raise "HTTP error: #{response.status}"
      end

      body_text = response.to_s
      parsed = JSON.parse(body_text)
      utcp_manual = UtcpManual.model_validate(parsed)
      return utcp_manual.tools
    rescue => e
      @log.error("Error discovering tools from '#{manual_provider.name}': #{e}")
      return []
    end
  end

  def deregister_tool_provider(manual_provider)
    return unless manual_provider.is_a?(StreamableHttpProvider)

    if @active_connections.key?(manual_provider.name)
      @log.info("Closing active HTTP stream connection for provider '#{manual_provider.name}'")
      conn = @active_connections.delete(manual_provider.name)
      client = conn[:client]
      client&.close if client.respond_to?(:close)
    end
  end

  def call_tool(tool_name, arguments, tool_provider)
    unless tool_provider.is_a?(StreamableHttpProvider)
      raise ArgumentError, "StreamableHttpClientTransport can only be used with StreamableHttpProvider"
    end

    request_headers = (tool_provider.headers || {}).dup
    body_content = nil
    remaining_args = arguments.dup

    if tool_provider.header_fields
      tool_provider.header_fields.each do |field|
        if remaining_args.key?(field)
          request_headers[field] = remaining_args.delete(field).to_s
        end
      end
    end

    if tool_provider.body_field && remaining_args.key?(tool_provider.body_field)
      body_content = remaining_args.delete(tool_provider.body_field)
    end

    url = build_url_with_path_params(tool_provider.url, remaining_args)
    query_params = remaining_args

    auth_header, cookies = apply_auth(tool_provider, request_headers, query_params)

    if tool_provider.auth.is_a?(OAuth2Auth)
      token = await handle_oauth2(tool_provider.auth)
      request_headers['Authorization'] = "Bearer #{token}"
    end

    # Prepare request
    method = tool_provider.http_method.to_s.downcase.to_sym
    timeout = tool_provider.timeout ? tool_provider.timeout / 1000.0 : 60.0

    request_opts = {
      headers: request_headers,
      params: query_params,
      cookies: cookies,
      timeout: timeout
    }

    if body_content
      request_headers['Content-Type'] ||= tool_provider.content_type
      if request_headers['Content-Type'].include?('application/json')
        request_opts[:json] = body_content
      else
        request_opts[:content] = body_content
      end
    end

    client = HTTPX.plugin(:stream).with(timeout: timeout)
    begin
      response = client.request(method, url, headers: request_headers, params: query_params, cookies: cookies, json: request_opts[:json], content: request_opts[:content])
      unless response.status.to_s.start_with?("2")
        raise "HTTP error: #{response.status}"
      end

      # Store active connection
      @active_connections[tool_provider.name] = { response: response, client: client }

      return process_http_stream(response, tool_provider.chunk_size, tool_provider.name)
    rescue => e
      client.close if client.respond_to?(:close)
      @log.error("Error establishing HTTP stream to '#{tool_provider.name}': #{e}")
      raise
    end
  end

  # Returns an async enumerator (Enumerator) that yields parsed chunks
  def process_http_stream(response, chunk_size, provider_name)
    Enumerator.new do |yielder|
      begin
        content_type = response.headers['content-type'] || ''

        if content_type.include?('application/x-ndjson')
          # Stream line by line
          response.read_body do |chunk|
            chunk.to_s.each_line do |line|
              next if line.strip.empty?
              begin
                yielder << JSON.parse(line)
              rescue JSON::ParserError
                @log.error("Error parsing NDJSON line for '#{provider_name}': #{line[0,100]}")
                yielder << line
              end
            end
          end
        elsif content_type.include?('application/octet-stream')
          response.read_body do |chunk|
            yielder << chunk if chunk && !chunk.empty?
          end
        elsif content_type.include?('application/json')
          buffer = ''
          response.read_body do |chunk|
            buffer << chunk.to_s
          end
          unless buffer.empty?
            begin
              yielder << JSON.parse(buffer)
            rescue JSON::ParserError
              @log.error("Error parsing JSON for '#{provider_name}': #{buffer[0,100]}")
              yielder << buffer
            end
          end
        else
          # Fallback: raw chunked binary
          response.read_body do |chunk|
            yielder << chunk if chunk && !chunk.empty?
          end
        end
      rescue => e
        @log.error("Error processing HTTP stream for '#{provider_name}': #{e}")
        raise
      ensure
        if @active_connections.key?(provider_name)
          conn = @active_connections[provider_name]
          # HTTPX does not require explicit close of response in typical usage
          # Remove from active if necessary
          # Optionally: client.close if you want to tear down immediately
        end
      end
    end
  end

  def handle_oauth2(auth_details)
    client_id = auth_details.client_id
    if @oauth_tokens.key?(client_id)
      return @oauth_tokens[client_id]['access_token']
    end

    # Try credentials in body first
    begin
      @log.info("Attempting OAuth2 token fetch for '#{client_id}' with credentials in body.")
      body = {
        grant_type: 'client_credentials',
        client_id: client_id,
        client_secret: auth_details.client_secret,
        scope: auth_details.scope
      }.compact

      response = HTTPX.post(auth_details.token_url, form: body, timeout: 10)
      unless response.status.to_s.start_with?("2")
        raise "Token endpoint error: #{response.status}"
      end
      token_data = JSON.parse(response.to_s)
      @oauth_tokens[client_id] = token_data
      return token_data['access_token']
    rescue => e
      @log.warn("OAuth2 with credentials in body failed: #{e}. Trying Basic Auth header.")
    end

    # Fallback: Basic Auth header
    begin
      @log.info("Attempting OAuth2 token fetch for '#{client_id}' with Basic Auth header.")
      basic = "#{client_id}:#{auth_details.client_secret}".encode64.strip
      headers = { 'Authorization' => "Basic #{basic}" }
      body = {
        grant_type: 'client_credentials',
        scope: auth_details.scope
      }.compact

      response = HTTPX.post(auth_details.token_url, headers: headers, form: body, timeout: 10)
      unless response.status.to_s.start_with?("2")
        raise "Token endpoint error: #{response.status}"
      end
      token_data = JSON.parse(response.to_s)
      @oauth_tokens[client_id] = token_data
      return token_data['access_token']
    rescue => e
      @log.error("OAuth2 with Basic Auth header also failed: #{e}")
      raise
    end
  end

  def build_url_with_path_params(url_template, arguments)
    url = url_template.dup
    path_params = url.scan(/\{([^}]+)\}/).flatten

    path_params.each do |param_name|
      if arguments.key?(param_name.to_sym) || arguments.key?(param_name)
        key = arguments.key?(param_name.to_sym) ? param_name.to_sym : param_name
        value = arguments.delete(key).to_s
        url.gsub!(/\{#{Regexp.escape(param_name)}\}/, value)
      else
        raise ArgumentError, "Missing required path parameter: #{param_name}"
      end
    end

    remaining = url.scan(/\{([^}]+)\}/).flatten
    unless remaining.empty?
      raise ArgumentError, "Missing required path parameters: #{remaining}"
    end

    url
  end

  private

  def log_error(msg)
    @log.error(msg)
  end
end
