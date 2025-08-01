# frozen_string_literal: true

class ValidationError < StandardError; end

module Auth
  def self.from_hash(h)
    raise ValidationError, "Expected a Hash" unless h.is_a?(Hash)

    case h.fetch("auth_type") { h.fetch(:auth_type) }
    when "api_key"
      ApiKeyAuth.new(h)
    when "basic"
      BasicAuth.new(h)
    when "oauth2"
      OAuth2Auth.new(h)
    else
      raise ValidationError, "Unknown auth_type: #{h['auth_type'] || h[:auth_type].inspect}"
    end
  end
end

class BaseAuth
  attr_reader :auth_type

  def initialize(auth_type:)
    @auth_type = auth_type
    validate_auth_type!
  end

  private

  def validate_auth_type!
    # subclasses can override if needed
    raise ValidationError, "auth_type must be a String" unless auth_type.is_a?(String)
  end
end

class ApiKeyAuth < BaseAuth
  ALLOWED_LOCATIONS = %w[header query cookie].freeze
  attr_reader :api_key, :var_name, :location

  def initialize(auth_type: "api_key", api_key:, var_name: "X-Api-Key", location: "header", **)
    super(auth_type: auth_type)
    @api_key = api_key.to_s
    @var_name = var_name.to_s
    @location = location.to_s

    validate!
  end

  def key_value
    if injected_variable?
      # e.g., "$MY_SECRET" -> lookup ENV["MY_SECRET"]
      env_var = api_key.sub(/\A\$/, "")
      ENV.fetch(env_var) { raise ValidationError, "Environment variable #{env_var} not set" }
    else
      api_key
    end
  end

  def injected_variable?
    api_key.start_with?("$")
  end

  private

  def validate!
    raise ValidationError, "api_key must be provided" if api_key.strip.empty?
    unless ALLOWED_LOCATIONS.include?(location)
      raise ValidationError, "location must be one of #{ALLOWED_LOCATIONS.inspect}"
    end
  end
end

class BasicAuth < BaseAuth
  attr_reader :username, :password

  def initialize(auth_type: "basic", username:, password:, **)
    super(auth_type: auth_type)
    @username = username.to_s
    @password = password.to_s

    validate!
  end

  private

  def validate!
    raise ValidationError, "username must be provided" if username.strip.empty?
    raise ValidationError, "password must be provided" if password.strip.empty?
  end
end

class OAuth2Auth < BaseAuth
  attr_reader :token_url, :client_id, :client_secret, :scope

  def initialize(auth_type: "oauth2", token_url:, client_id:, client_secret:, scope: nil, **)
    super(auth_type: auth_type)
    @token_url = token_url.to_s
    @client_id = client_id.to_s
    @client_secret = client_secret.to_s
    @scope = scope&.to_s

    validate!
  end

  private

  def validate!
    raise ValidationError, "token_url must be provided" if token_url.strip.empty?
    raise ValidationError, "client_id must be provided" if client_id.strip.empty?
    raise ValidationError, "client_secret must be provided" if client_secret.strip.empty?
  end
end