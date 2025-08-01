class Tool
  attr_accessor :name, :description, :tags, :input_schema, :output_schema, :tool_provider

  def initialize(name:, description: nil, tags: [], input_schema: nil, output_schema: nil, tool_provider: nil, **_extra)
    @name = name
    @description = description
    @tags = tags || []
    @input_schema = input_schema
    @output_schema = output_schema
    @tool_provider = tool_provider
  end

  def self.model_validate(hash)
    raise ArgumentError, "Expected a Hash" unless hash.is_a?(Hash)

    new(**hash.transform_keys(&:to_sym))
  end
end

class UtcpManual
  attr_accessor :tools

  def initialize(tools: [])
    @tools = tools
  end

  def self.model_validate(hash)
    raise ArgumentError, "Expected a Hash" unless hash.is_a?(Hash)

    tools = (hash[:tools] || hash['tools'] || []).map do |tool|
      tool.is_a?(Tool) ? tool : Tool.model_validate(tool)
    end

    new(tools: tools)
  end
end

require 'ostruct'

class Provider < OpenStruct
  def initialize(name:, provider_type:, **attrs)
    super(attrs.merge(name: name, provider_type: provider_type))
  end

  def self.model_validate(hash)
    new(**hash.transform_keys(&:to_sym))
  end

  def model_dump
    to_h
  end
end

class HttpProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'http', **attrs)
  end
end

class StreamableHttpProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'http_stream', **attrs)
  end
end

class CliProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'cli', **attrs)
  end
end

class TextProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'text', **attrs)
  end
end

class SSEProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'sse', **attrs)
  end
end

class MCPProvider < Provider
  def initialize(name:, config:, **attrs)
    super(name: name, provider_type: 'mcp', config: self.class.deep_ostruct(config), **attrs)
  end

  def self.deep_ostruct(obj)
    case obj
    when Hash
      OpenStruct.new(obj.transform_values { |v| deep_ostruct(v) })
    when Array
      obj.map { |v| deep_ostruct(v) }
    else
      obj
    end
  end
end

class GraphQLProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'graphql', **attrs)
  end
end

class WebSocketProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'websocket', **attrs)
  end
end

class GRPCProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'grpc', **attrs)
  end
end

class TCPProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'tcp', **attrs)
  end
end

class UDPProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'udp', **attrs)
  end
end

class WebRTCProvider < Provider
  def initialize(name:, **attrs)
    super(name: name, provider_type: 'webrtc', **attrs)
  end
end

class ApiKeyAuth
  attr_accessor :api_key, :var_name, :location

  def initialize(api_key:, var_name:, location: 'header')
    @api_key = api_key
    @var_name = var_name
    @location = location
  end
end

class BasicAuth
  attr_accessor :username, :password

  def initialize(username:, password:)
    @username = username
    @password = password
  end
end

class OAuth2Auth
  attr_accessor :client_id, :client_secret, :token_url, :scope

  def initialize(client_id:, client_secret:, token_url:, scope: nil)
    @client_id = client_id
    @client_secret = client_secret
    @token_url = token_url
    @scope = scope
  end
end
