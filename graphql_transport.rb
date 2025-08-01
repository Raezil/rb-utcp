require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'graphql/client'
require 'graphql/client/http'
require 'logger'

# Simple in-memory OAuth2 token cache
class OAuth2TokenCache
  def initialize
    @cache = {}
  end

  def fetch(client_id)
    @cache[client_id]
  end

  def store(client_id, token_response)
    @cache[client_id] = token_response
  end

  def clear
    @cache.clear
  end
end

class GraphQLClientTransport
  # logger: callable like ->(msg, error: false) { ... }
  def initialize(logger: nil)
    @log = logger || proc { |msg, **_| } # no-op
    @oauth_tokens = OAuth2TokenCache.new
  end

  def enforce_https_or_localhost!(url)
    unless url.start_with?('https://') ||
           url.start_with?('http://localhost') ||
           url.start_with?('http://127.0.0.1')
      raise ArgumentError,
            "Security error: URL must use HTTPS or start with 'http://localhost' or 'http://127.0.0.1'. Got: #{url}. Non-secure URLs are vulnerable to man-in-the-middle attacks."
    end
  end

  def handle_oauth2(auth)
    client_id = auth.client_id
    cached = @oauth_tokens.fetch(client_id)
    return cached['access_token'] if cached

    uri = URI.parse(auth.token_url)
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(
      'grant_type' => 'client_credentials',
      'client_id' => client_id,
      'client_secret' => auth.client_secret,
      'scope' => auth.scope
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    resp = http.request(req)
    unless resp.is_a?(Net::HTTPSuccess)
      raise "OAuth2 token request failed: #{resp.code} #{resp.body}"
    end

    token_response = JSON.parse(resp.body)
    @oauth_tokens.store(client_id, token_response)
    t
