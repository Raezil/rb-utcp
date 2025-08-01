require 'async'
require 'async/http/internet'
require 'json'
require 'uri'
require 'base64'
require_relative 'models'

# Placeholder auth classes; assume real ones exist in your codebase.
# class ApiKeyAuth; attr_accessor :api_key, :location, :var_name; end
# class BasicAuth; attr_accessor :username, :password; end
# class OAuth2Auth; attr_accessor :client_id, :client_secret, :token_url, :scope; end

class SSEClientTransport
  # Client transport implementation for Server-Sent Events providers.

  def initialize(logger: nil)
    @oauth_tokens = {} # client_id => token hash
    @log = logger || ->(*args) {}
    @active_connections = {} # provider_name => [response, internet]
  end

  # Example usage:
  #   provider = SSEProvider.new(name: 'example', url: 'https://example.com/events')
  #   transport = SSEClientTransport.new
  #   enum = transport.call_tool('stream', {}, provider)
  #   enum.each { |event| puts event }

  # Apply authentication similar to Python version.
  # Returns [auth_header_hash, cookies_hash]
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
            raise "Unknown ApiKeyAuth location: #{provider.auth.location}"
          end
        else
          @log.call("API key not found for ApiKeyAuth.", error: true)
          raise ArgumentError, 'API key for ApiKeyAuth not found.'
        end
      when BasicAuth
        # Basic Auth will be set later in request construction
        # We'll encode it in header form here:
        credential = Base64.strict_encode64("#{provider.auth.username}:#{provider.auth.password}")
        headers['Authorization'] = "Basic #{credential}"
      when OAuth2Auth
        # Handled separately (async)
      end
    end

    [headers, cookies]
  end

  def register_tool_provider(manual_provider)
    unless manual_provider.is_a?(SSEProvider)
      raise ArgumentError, 'SSEClientTransport can only be used with SSEProvider'
    end

    begin
      url = manual_provider.url

      unless url.start_with?('https://') || url.start_with?('http://localhost') || url.start_with?('http://127.0.0.1')
        raise ArgumentError, "Security error: URL must use HTTPS or localhost. Got: #{url}"
      end

      @log.call("Discovering tools from '#{manual_provider.name}' (SSE) at #{url}")

      headers = manual_provider.headers ? manual_provider.headers.dup : {}
      query_params = {}

      # Apply standard auth (OAuth2 special)
      headers, cookies = apply_auth(manual_provider, headers, query_params)

      if manual_provider.auth.is_a?(OAuth2Auth)
        token = handle_oauth2(manual_provider.auth)
        headers['Authorization'] = "Bearer #{token}"
      end

      body_content = nil
      if manual_provider.body_field
        # Support if needed; here none for discovery
        body_content = nil
      end

      # Build and perform request
      Async do
        internet = Async::HTTP::Internet.new

        begin
          # Prepare request
          request_headers = headers.dup
          if body_content && !request_headers.key?('Content-Type')
            request_headers['Content-Type'] = 'application/json'
          end

          body = nil
          if body_content
            if request_headers['Content-Type']&.include?('application/json')
              body = JSON.generate(body_content)
            else
              body = body_content.to_s
            end
          end

          # Assemble query string
          uri = URI.parse(url)
          unless query_params.empty?
            uri.query = URI.encode_www_form(query_params)
          end

          response = internet.get(
            uri.to_s,
            request_headers
          )

          unless response.status.between?(200, 299)
            raise "HTTP Error: #{response.status} - #{response.read}"
          end

          data = JSON.parse(response.read)
          utcp_manual = UtcpManual.model_validate(data)
          return utcp_manual.tools
        ensure
          internet.close
        end
      end
    rescue => e
      @log.call("Error discovering tools from '#{manual_provider.name}': #{e}", error: true)
      return []
    end
  end

  def deregister_tool_provider(manual_provider)
    if @active_connections.key?(manual_provider.name)
      @log.call("Closing active SSE connection for provider '#{manual_provider.name}'")
      response, internet = @active_connections.delete(manual_provider.name)
      # Close low-level resources if available
      response.close if response.respond_to?(:close)
      internet.close if internet.respond_to?(:close)
    end
  end

  def call_tool(tool_name, arguments, tool_provider)
    unless tool_provider.is_a?(SSEProvider)
      raise ArgumentError, 'SSEClientTransport can only be used with SSEProvider'
    end

    headers = tool_provider.headers ? tool_provider.headers.dup : {}
    headers['Accept'] = 'text/event-stream'
    body_content = nil
    remaining_args = arguments.dup

    if tool_provider.header_fields
      tool_provider.header_fields.each do |field_name|
        if remaining_args.key?(field_name)
          headers[field_name] = remaining_args.delete(field_name).to_s
        end
      end
    end

    if tool_provider.body_field && remaining_args.key?(tool_provider.body_field)
      body_content = remaining_args.delete(tool_provider.body_field)
    end

    # Build URL with path params
    url = build_url_with_path_params(tool_provider.url, remaining_args)
    query_params = remaining_args

    headers, cookies = apply_auth(tool_provider, headers, query_params)

    if tool_provider.auth.is_a?(OAuth2Auth)
      token = await(handle_oauth2(tool_provider.auth))
      headers['Authorization'] = "Bearer #{token}"
    end

    # Use Async HTTP client
    Async do
      internet = Async::HTTP::Internet.new
      begin
        method = body_content ? :post : :get
        request_headers = headers.dup
        if body_content && !request_headers.key?('Content-Type')
          request_headers['Content-Type'] = 'application/json'
        end

        body = nil
        if body_content
          if request_headers['Content-Type']&.include?('application/json')
            body = JSON.generate(body_content)
          else
            body = body_content.to_s
          end
        end

        uri = URI.parse(url)
        unless query_params.empty?
          uri.query = URI.encode_www_form(query_params)
        end

        response = internet.send(
          method,
          uri.to_s,
          request_headers,
          body
        )

        unless response.status.between?(200, 299)
          raise "Failed to establish SSE connection: #{response.status} - #{response.read}"
        end

        # Store active connection for later cleanup
        @active_connections[tool_provider.name] = [response, internet]

        # Return an async enumerator for SSE events
        return enum_for(:process_sse_stream, response, tool_provider.event_type)
      rescue => e
        internet.close
        @log.call("Error establishing SSE connection to '#{tool_provider.name}': #{e}", error: true)
        raise
      end
    end
  end

  # Synchronous enumerator to be used with Ruby's Enumerator or custom iteration.
  def process_sse_stream(response, event_type = nil)
    buffer = ''
    # Assuming response is something yielding chunks; emulate `async` streaming behavior
    reader = response.finish.read_body rescue nil
    if reader.nil? && response.respond_to?(:each)
      enumerable = response
    else
      # Fallback: entire body as one chunk
      enumerable = [response.read]
    end

    enumerable.each do |chunk|
      buffer << chunk.to_s

      while buffer.include?("\n\n")
        event_string, buffer = buffer.split("\n\n", 2)
        next if event_string.strip.empty?

        current_event = {}
        data_lines = []

        event_string.each_line do |line|
          next if line.start_with?(':')

          if line.include?(':')
            field, value = line.split(':', 2)
            value = value.lstrip.chomp
            case field
            when 'event'
              current_event['event'] = value
            when 'data'
              data_lines << value
            when 'id'
              current_event['id'] = value
            when 'retry'
              begin
                current_event['retry'] = Integer(value)
              rescue
              end
            end
          end
        end

        next if data_lines.empty?

        current_event['data'] = data_lines.join("\n")

        if event_type && current_event['event'] != event_type
          next
        end

        begin
          parsed = JSON.parse(current_event['data'])
          yield parsed
        rescue JSON::ParserError
          yield current_event['data']
        end
      end
    end
  rescue => e
    @log.call("Error processing SSE stream: #{e}", error: true)
    raise
  end

  def handle_oauth2(auth_details)
    client_id = auth_details.client_id
    if @oauth_tokens.key?(client_id)
      return @oauth_tokens[client_id]['access_token']
    end

    Async do
      internet = Async::HTTP::Internet.new
      begin
        # Method 1: credentials in body
        body = {
          'grant_type' => 'client_credentials',
          'client_id' => client_id,
          'client_secret' => auth_details.client_secret,
          'scope' => auth_details.scope
        }

        response = internet.post(auth_details.token_url, { 'Content-Type' => 'application/x-www-form-urlencoded' }, URI.encode_www_form(body))
        if response.status.between?(200, 299)
          token_response = JSON.parse(response.read)
          @oauth_tokens[client_id] = token_response
          return token_response['access_token']
        else
          @log.call("OAuth2 with body failed: #{response.status} #{response.read}. Trying header fallback.")
        end
      rescue => e
        @log.call("OAuth2 with body failed: #{e}. Trying Basic Auth.")
      ensure
        # Continue to header method if needed
      end

      # Method 2: Basic auth header
      begin
        header_credential = Base64.strict_encode64("#{client_id}:#{auth_details.client_secret}")
        headers = {
          'Authorization' => "Basic #{header_credential}",
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
        body = { 'grant_type' => 'client_credentials', 'scope' => auth_details.scope }
        response = internet.post(auth_details.token_url, headers, URI.encode_www_form(body))
        if response.status.between?(200, 299)
          token_response = JSON.parse(response.read)
          @oauth_tokens[client_id] = token_response
          return token_response['access_token']
        else
          @log.call("OAuth2 with header failed: #{response.status} #{response.read}")
          raise "OAuth2 token retrieval failed with header method"
        end
      rescue => e
        @log.call("OAuth2 with header failed: #{e}")
        raise
      ensure
        internet.close
      end
    end
  end

  def close
    @active_connections.keys.each do |provider_name|
      if @active_connections.key?(provider_name)
        response, internet = @active_connections.delete(provider_name)
        response.close if response.respond_to?(:close)
        internet.close if internet.respond_to?(:close)
      end
    end
    @active_connections.clear
  end

  def build_url_with_path_params(url_template, arguments)
    path_params = url_template.scan(/\{([^}]+)\}/).flatten
    url = url_template.dup

    path_params.each do |param_name|
      if arguments.key?(param_name)
        param_value = arguments.delete(param_name).to_s
        url.gsub!("{#{param_name}}", param_value)
      else
        raise ArgumentError, "Missing required path parameter: #{param_name}"
      end
    end

    remaining_placeholders = url.scan(/\{([^}]+)\}/).flatten
    unless remaining_placeholders.empty?
      raise ArgumentError, "Missing required path parameters: #{remaining_placeholders}"
    end

    url
  end
end
