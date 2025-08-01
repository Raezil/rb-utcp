require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'base64'
require 'logger'
require 'openssl'
require_relative 'models'

class HttpClientTransport
  # logger: proc { |msg, error: false| ... }
  def initialize(logger: nil)
    @logger = logger || proc { |*args, **_kwargs| } # no-op
    @oauth_tokens = {}
  end

  # Example usage:
  #   provider = HttpProvider.new(name: 'example', url: 'https://example.com/manual.json')
  #   transport = HttpClientTransport.new
  #   tools = transport.register_tool_provider(provider)
  #   result = transport.call_tool(tool_name: tools.first.name, arguments: {}, tool_provider: provider)

  # Discover tools from a REST provider (synchronous version)
  def register_tool_provider(manual_provider)
    unless manual_provider.is_a?(HttpProvider)
      raise ArgumentError, 'HttpClientTransport can only be used with HttpProvider'
    end

    begin
      url = manual_provider.url
      enforce_https_or_localhost!(url)

      @logger.call("Discovering tools from '#{manual_provider.name}' (REST) at #{url}")

      request_headers = (manual_provider.headers || {}).dup
      query_params = {}
      body_content = nil

      auth_obj, cookies = apply_auth(manual_provider, request_headers, query_params)

      # OAuth2 requires token fetch
      if manual_provider.auth.is_a?(OAuth2Auth)
        token = handle_oauth2(manual_provider.auth)
        request_headers['Authorization'] = "Bearer #{token}"
      end

      uri = URI.parse(url)
      unless query_params.empty?
        uri.query = URI.encode_www_form(query_params)
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.read_timeout = 10
      http.open_timeout = 5

      req_class = Net::HTTP.const_get(manual_provider.http_method.capitalize)
      request = req_class.new(uri)
      request.initialize_http_header(request_headers)
      # Attach cookies if any
      unless cookies.empty?
        cookie_header = cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
        request['Cookie'] = cookie_header
      end

      # Body handling (discovery typically doesn't have body)
      if body_content
        if request['Content-Type']&.include?('application/json')
          request.body = body_content.to_json
        else
          request.body = body_content
        end
      end

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        @logger.call("Error connecting to REST provider '#{manual_provider.name}': #{response.code} #{response.body}", error: true)
        return []
      end

      content_type = response['Content-Type'] || ''
      body_text = response.body

      if content_type.include?('yaml') || url.match?(/\.ya?ml$/)
        response_data = YAML.safe_load(body_text)
      else
        response_data = JSON.parse(body_text)
      end

      if response_data.is_a?(Hash) && response_data.key?('tools')
        @logger.call("Detected UTCP manual from '#{manual_provider.name}'.")
        utcp_manual = UtcpManual.model_validate(response_data)
      else
        @logger.call("Assuming OpenAPI spec from '#{manual_provider.name}'. Converting to UTCP manual.")
        converter = OpenApiConverter.new(response_data, spec_url: manual_provider.url, provider_name: manual_provider.name)
        utcp_manual = converter.convert
      end

      utcp_manual.tools
    rescue JSON::ParserError, Psych::SyntaxError => e
      @logger.call("Error parsing spec from REST provider '#{manual_provider.name}': #{e}", error: true)
      []
    rescue StandardError => e
      @logger.call("Unexpected error discovering tools from REST provider '#{manual_provider.name}': #{e}", error: true)
      []
    end
  end

  def deregister_tool_provider(_manual_provider)
    # No-op; stateless
  end

  def call_tool(tool_name:, arguments:, tool_provider:)
    unless tool_provider.is_a?(HttpProvider)
      raise ArgumentError, 'HttpClientTransport can only be used with HttpProvider'
    end

    request_headers = (tool_provider.headers || {}).dup
    body_content = nil
    remaining_args = arguments.dup

    # Header fields
    if tool_provider.header_fields
      tool_provider.header_fields.each do |field_name|
        if remaining_args.key?(field_name)
          request_headers[field_name] = remaining_args.delete(field_name).to_s
        end
      end
    end

    # Body field
    if tool_provider.body_field && remaining_args.key?(tool_provider.body_field)
      body_content = remaining_args.delete(tool_provider.body_field)
    end

    # Path param substitution
    url = build_url_with_path_params(tool_provider.url, remaining_args)

    # Remaining args become query params
    query_params = remaining_args

    auth_obj, cookies = apply_auth(tool_provider, request_headers, query_params)

    if tool_provider.auth.is_a?(OAuth2Auth)
      token = handle_oauth2(tool_provider.auth)
      request_headers['Authorization'] = "Bearer #{token}"
    end

    uri = URI.parse(url)
    unless query_params.empty?
      uri.query = URI.encode_www_form(query_params)
    end

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.read_timeout = 30
      http.open_timeout = 5

      req_class = Net::HTTP.const_get(tool_provider.http_method.capitalize)
      request = req_class.new(uri)
      request.initialize_http_header(request_headers)

      # Cookies
      unless cookies.empty?
        cookie_header = cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
        request['Cookie'] = cookie_header
      end

      if body_content
        if request['Content-Type']&.include?('application/json') || tool_provider.content_type&.include?('application/json')
          request['Content-Type'] ||= 'application/json'
          request.body = body_content.is_a?(String) ? body_content : body_content.to_json
        else
          request.body = body_content
        end
      end

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        msg = "Error calling tool '#{tool_name}' on provider '#{tool_provider.name}': #{response.code} #{response.body}"
        @logger.call(msg, error: true)
        raise StandardError, msg
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      @logger.call("Failed to parse JSON response for tool '#{tool_name}': #{e}", error: true)
      raise
    rescue StandardError => e
      @logger.call("Unexpected error calling tool '#{tool_name}': #{e}", error: true)
      raise
    end
  end

  private

  def enforce_https_or_localhost!(url)
    unless url.start_with?('https://') ||
           url.start_with?('http://localhost') ||
           url.start_with?('http://127.0.0.1')
      raise ArgumentError,
            "Security error: URL must use HTTPS or start with 'http://localhost' or 'http://127.0.0.1'. Got: #{url}. Non-secure URLs are vulnerable to man-in-the-middle attacks."
    end
  end

  # Returns [auth_obj, cookies_hash]
  def apply_auth(provider, headers, query_params)
    auth_obj = nil
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
          end
        else
          @logger.call('API key not found for ApiKeyAuth.', error: true)
          raise ArgumentError, 'API key for ApiKeyAuth not found.'
        end
      when BasicAuth
        basic = "#{provider.auth.username}:#{provider.auth.password}"
        encoded = Base64.strict_encode64(basic)
        headers['Authorization'] = "Basic #{encoded}"
      when OAuth2Auth
        # handled separately in caller because it may be async-like
      end
    end

    [auth_obj, cookies]
  end

  # Handles OAuth2 client credentials with fallback to header method
  def handle_oauth2(auth_details)
    client_id = auth_details.client_id
    if @oauth_tokens.key?(client_id)
      return @oauth_tokens[client_id]['access_token']
    end

    uri = URI.parse(auth_details.token_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 10
    http.open_timeout = 5

    # Try credentials in body first
    begin
      @logger.call('Attempting OAuth2 token fetch with credentials in body.')
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        'grant_type' => 'client_credentials',
        'client_id' => auth_details.client_id,
        'client_secret' => auth_details.client_secret,
        'scope' => auth_details.scope
      )

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise "OAuth2 token fetch failed (body): #{response.code} #{response.body}"
      end

      token_response = JSON.parse(response.body)
      @oauth_tokens[client_id] = token_response
      return token_response['access_token']
    rescue StandardError => e
      @logger.call("OAuth2 with credentials in body failed: #{e}. Trying Basic Auth header.")
    end

    # Fallback to Basic Auth header
    begin
      @logger.call('Attempting OAuth2 token fetch with Basic Auth header.')
      request = Net::HTTP::Post.new(uri)
      request.set_form_data('grant_type' => 'client_credentials', 'scope' => auth_details.scope)
      basic = "#{auth_details.client_id}:#{auth_details.client_secret}"
      encoded = Base64.strict_encode64(basic)
      request['Authorization'] = "Basic #{encoded}"

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise "OAuth2 token fetch failed (header): #{response.code} #{response.body}"
      end

      token_response = JSON.parse(response.body)
      @oauth_tokens[client_id] = token_response
      return token_response['access_token']
    rescue StandardError => e
      @logger.call("OAuth2 with Basic Auth header also failed: #{e}", error: true)
      raise
    end
  end

  # Substitute {param} in URL and remove from arguments
  def build_url_with_path_params(url_template, arguments)
    url = url_template.dup
    path_params = url.scan(/\{([^}]+)\}/).flatten

    path_params.each do |param_name|
      if arguments.key?(param_name)
        param_value = arguments.delete(param_name).to_s
        url.gsub!("{#{param_name}}", param_value)
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
end
