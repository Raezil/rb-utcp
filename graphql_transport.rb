require 'net/http'
require 'uri'
require 'json'
require 'logger'
require_relative 'models'

class OAuth2TokenCache
  def initialize
    @cache = {}
  end

  def fetch(client_id)
    @cache[client_id]
  end

  def store(client_id, token)
    @cache[client_id] = token
  end

  def clear
    @cache.clear
  end
end

class GraphQLClientTransport
  def initialize(logger: nil)
    @log = logger || proc { |_msg, **_k| }
    @oauth_tokens = OAuth2TokenCache.new
  end

  # Example usage:
  #   provider = GraphQLProvider.new(name: 'example', url: 'https://example.com/graphql')
  #   transport = GraphQLClientTransport.new
  #   result = transport.call_tool('query', { query: '{ hello }' }, provider)

  def enforce_https_or_localhost!(url)
    unless url.start_with?('https://') || url.start_with?('http://localhost') || url.start_with?('http://127.0.0.1')
      raise ArgumentError, "Security error: URL must use HTTPS or localhost. Got: #{url}"
    end
  end

  def handle_oauth2(auth)
    cached = @oauth_tokens.fetch(auth.client_id)
    return cached['access_token'] if cached

    uri = URI.parse(auth.token_url)
    req = Net::HTTP::Post.new(uri)
    req.set_form_data('grant_type' => 'client_credentials', 'client_id' => auth.client_id,
                      'client_secret' => auth.client_secret, 'scope' => auth.scope)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    resp = http.request(req)
    raise "OAuth2 token request failed: #{resp.code} #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)
    token_response = JSON.parse(resp.body)
    @oauth_tokens.store(auth.client_id, token_response)
    token_response['access_token']
  end

  def register_tool_provider(_manual_provider)
    []
  end

  def deregister_tool_provider(_provider); end

  def call_tool(_tool_name, arguments, tool_provider)
    enforce_https_or_localhost!(tool_provider.url)
    headers = (tool_provider.headers || {}).dup
    if tool_provider.auth.is_a?(OAuth2Auth)
      token = handle_oauth2(tool_provider.auth)
      headers['Authorization'] = "Bearer #{token}"
    end
    query = arguments[:query] || arguments['query']
    variables = arguments[:variables] || arguments['variables'] || {}
    raise ArgumentError, 'query is required' unless query

    uri = URI.parse(tool_provider.url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    req = Net::HTTP::Post.new(uri)
    req.initialize_http_header(headers)
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump({ query: query, variables: variables })
    resp = http.request(req)
    raise "GraphQL request failed: #{resp.code} #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)
    JSON.parse(resp.body)
  end
end
