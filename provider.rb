# frozen_string_literal: true

require 'securerandom'
require 'uri'

class ValidationError < StandardError; end

# === Auth classes are assumed to exist similarly to previous snippet ===
# ApiKeyAuth, BasicAuth, OAuth2Auth, and Auth.from_hash should be defined elsewhere
# and behave like in the earlier provided Ruby version.

# --- Provider hierarchy and union logic ---

module Provider
  def self.from_hash(h)
    raise ValidationError, "Expected a Hash" unless h.is_a?(Hash)

    type = fetch_value(h, :provider_type) || fetch_value(h, 'provider_type')
    case type
    when 'http'
      HttpProvider.new(h)
    when 'sse'
      SSEProvider.new(h)
    when 'http_stream'
      StreamableHttpProvider.new(h)
    when 'cli'
      CliProvider.new(h)
    when 'websocket'
      WebSocketProvider.new(h)
    when 'grpc'
      GRPCProvider.new(h)
    when 'graphql'
      GraphQLProvider.new(h)
    when 'tcp'
      TCPProvider.new(h)
    when 'udp'
      UDPProvider.new(h)
    when 'webrtc'
      WebRTCProvider.new(h)
    when 'mcp'
      MCPProvider.new(h)
    when 'text'
      TextProvider.new(h)
    else
      raise ValidationError, "Unknown provider_type: #{type.inspect}"
    end
  end

  def self.fetch_value(h, key)
    h[key] if h.key?(key)
  end
end

class BaseProvider
  attr_reader :name, :provider_type

  def initialize(name: nil, provider_type:, **kwargs)
    @name = name || SecureRandom.hex
    @provider_type = provider_type
    validate_provider_type!(provider_type)
  end

  private

  def validate_provider_type!(v)
    raise ValidationError, "provider_type must be a string" unless v.is_a?(String)
  end
end

# --- Concrete Providers ---

class HttpProvider < BaseProvider
  ALLOWED_METHODS = %w[GET POST PUT DELETE PATCH].freeze
  attr_reader :http_method, :url, :content_type, :auth, :headers, :body_field, :header_fields

  def initialize(provider_type: 'http', http_method: 'GET', url:, content_type: 'application/json',
                 auth: nil, headers: nil, body_field: 'body', header_fields: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @http_method = http_method
    @url = url
    @content_type = content_type
    @auth = auth && Auth.from_hash(auth)
    @headers = headers
    @body_field = body_field
    @header_fields = header_fields

    validate!
  end

  private

  def validate!
    unless ALLOWED_METHODS.include?(@http_method)
      raise ValidationError, "http_method must be one of #{ALLOWED_METHODS.inspect}"
    end

    raise ValidationError, "url must be a valid URI" unless valid_uri?(@url)
  end

  def valid_uri?(u)
    !!(URI.parse(u) rescue false)
  end
end

class SSEProvider < BaseProvider
  attr_reader :url, :event_type, :reconnect, :retry_timeout, :auth, :headers, :body_field, :header_fields

  def initialize(provider_type: 'sse', url:, event_type: nil, reconnect: true, retry_timeout: 30_000,
                 auth: nil, headers: nil, body_field: nil, header_fields: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @url = url
    @event_type = event_type
    @reconnect = reconnect
    @retry_timeout = retry_timeout
    @auth = auth && Auth.from_hash(auth)
    @headers = headers
    @body_field = body_field
    @header_fields = header_fields

    validate!
  end

  private

  def validate!
    raise ValidationError, "url must be a valid URI" unless valid_uri?(@url)
    unless [true, false].include?(@reconnect)
      raise ValidationError, "reconnect must be boolean"
    end
    raise ValidationError, "retry_timeout must be non-negative integer" unless @retry_timeout.is_a?(Integer) && @retry_timeout >= 0
  end

  def valid_uri?(u)
    !!(URI.parse(u) rescue false)
  end
end

class StreamableHttpProvider < BaseProvider
  attr_reader :url, :http_method, :content_type, :chunk_size, :timeout, :headers, :auth, :body_field, :header_fields

  def initialize(provider_type: 'http_stream', url:, http_method: 'GET', content_type: 'application/octet-stream',
                 chunk_size: 4096, timeout: 60_000, headers: nil, auth: nil, body_field: nil, header_fields: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @url = url
    @http_method = http_method
    @content_type = content_type
    @chunk_size = chunk_size
    @timeout = timeout
    @headers = headers
    @auth = auth && Auth.from_hash(auth)
    @body_field = body_field
    @header_fields = header_fields

    validate!
  end

  private

  def validate!
    unless %w[GET POST].include?(@http_method)
      raise ValidationError, "http_method must be 'GET' or 'POST'"
    end
    raise ValidationError, "chunk_size must be positive integer" unless @chunk_size.is_a?(Integer) && @chunk_size > 0
    raise ValidationError, "timeout must be non-negative integer" unless @timeout.is_a?(Integer) && @timeout >= 0
    raise ValidationError, "url must be a valid URI" unless valid_uri?(@url)
  end

  def valid_uri?(u)
    !!(URI.parse(u) rescue false)
  end
end

class CliProvider < BaseProvider
  attr_reader :command_name, :env_vars, :working_dir

  def initialize(provider_type: 'cli', command_name:, env_vars: nil, working_dir: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @command_name = command_name
    @env_vars = env_vars
    @working_dir = working_dir
    # auth is always nil for CLI
    validate!
  end

  private

  def validate!
    raise ValidationError, "command_name must be provided" if @command_name.to_s.strip.empty?
  end
end

class WebSocketProvider < BaseProvider
  attr_reader :url, :protocol, :keep_alive, :auth, :headers, :header_fields

  def initialize(provider_type: 'websocket', url:, protocol: nil, keep_alive: true,
                 auth: nil, headers: nil, header_fields: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @url = url
    @protocol = protocol
    @keep_alive = keep_alive
    @auth = auth && Auth.from_hash(auth)
    @headers = headers
    @header_fields = header_fields

    validate!
  end

  private

  def validate!
    raise ValidationError, "url must be a valid URI" unless valid_uri?(@url)
    unless [true, false].include?(@keep_alive)
      raise ValidationError, "keep_alive must be boolean"
    end
  end

  def valid_uri?(u)
    !!(URI.parse(u) rescue false)
  end
end

class GRPCProvider < BaseProvider
  attr_reader :host, :port, :service_name, :method_name, :use_ssl, :auth

  def initialize(provider_type: 'grpc', host:, port:, service_name:, method_name:, use_ssl: false,
                 auth: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @host = host
    @port = port
    @service_name = service_name
    @method_name = method_name
    @use_ssl = use_ssl
    @auth = auth && Auth.from_hash(auth)

    validate!
  end

  private

  def validate!
    raise ValidationError, "host must be provided" if @host.to_s.strip.empty?
    raise ValidationError, "port must be integer between 1 and 65535" unless @port.is_a?(Integer) && (1..65_535).include?(@port)
    raise ValidationError, "service_name must be provided" if @service_name.to_s.strip.empty?
    raise ValidationError, "method_name must be provided" if @method_name.to_s.strip.empty?
  end
end

class GraphQLProvider < BaseProvider
  ALLOWED_OPERATION_TYPES = %w[query mutation subscription].freeze
  attr_reader :url, :operation_type, :operation_name, :auth, :headers, :header_fields

  def initialize(provider_type: 'graphql', url:, operation_type: 'query', operation_name: nil,
                 auth: nil, headers: nil, header_fields: nil, name: nil, **)
    super(name: name, provider_type: provider_type)
    @url = url
    @operation_type = operation_type
    @operation_name = operation_name
    @auth = auth && Auth.from_hash(auth)
    @headers = headers
    @header_fields = header_fields

    validate!
  end

  private

  def validate!
    unless ALLOWED_OPERATION_TYPES.include?(@operation_type)
      raise ValidationError, "operation_type must be one of #{ALLOWED_OPERATION_TYPES.inspect}"
    end
    raise ValidationError, "url must be a valid URI" unless valid_uri?(@url)
  end

  def valid_uri?(u)
    !!(URI.parse(u) rescue false)
  end
end

class TCPProvider < BaseProvider
  attr_read_
