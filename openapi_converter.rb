require 'uri'
require 'json'
require 'set'

class OpenApiConverter
  # Converts an OpenAPI JSON specification into a UtcpManual.

  # @param openapi_spec [Hash]
  # @param spec_url [String, nil]
  # @param provider_name [String, nil]
  def initialize(openapi_spec, spec_url: nil, provider_name: nil)
    @spec = openapi_spec
    @spec_url = spec_url
    if provider_name.nil?
      title = openapi_spec.dig('info', 'title') || 'openapi_provider'
      invalid_chars = " -.,!?'\"\\\\/()[]{}#@$%^&*+=~`|;:<>"
      @provider_name = title.chars.map { |c| invalid_chars.include?(c) ? '_' : c }.join
    else
      @provider_name = provider_name
    end
  end

  # Parses the OpenAPI specification and returns a UtcpManual.
  # @return [UtcpManual]
  def convert
    tools = []

    base_url = if @spec['servers'] && @spec['servers'].any?
                 @spec['servers'][0]['url']
               elsif @spec_url
                 parsed = URI.parse(@spec_url)
                 "#{parsed.scheme}://#{parsed.host}"
               else
                 warn "No server info or spec URL provided. Using fallback base URL: /"
                 '/'
               end

    (@spec['paths'] || {}).each do |path, path_item|
      path_item.each do |method, operation|
        if %w[get post put delete patch].include?(method.to_s.downcase)
          tool = create_tool(path, method, operation, base_url)
          tools << tool if tool
        end
      end
    end

    UtcpManual.new(tools: tools)
  end

  private

  # Resolves a local JSON reference like "#/components/schemas/Foo"
  def resolve_ref(ref)
    unless ref.start_with?('#/')
      raise ArgumentError, "External or non-local references are not supported: #{ref}"
    end

    parts = ref[2..].split('/')
    node = @spec
    parts.each do |part|
      if node.is_a?(Hash) && node.key?(part)
        node = node[part]
      else
        raise ArgumentError, "Reference not found: #{ref}"
      end
    end
    node
  end

  # Recursively resolves $refs inside a schema or nested structure.
  def resolve_schema(schema)
    case schema
    when Hash
      if schema.key?('$ref')
        resolved = resolve_ref(schema['$ref'])
        return resolve_schema(resolved)
      end

      result = {}
      schema.each do |k, v|
        result[k] = resolve_schema(v)
      end
      result
    when Array
      schema.map { |item| resolve_schema(item) }
    else
      schema
    end
  end

  # Extracts authentication information for an operation.
  def extract_auth(operation)
    security_requirements = operation['security'] || []

    if security_requirements.empty?
      security_requirements = @spec['security'] || []
    end

    return nil if security_requirements.empty?

    security_schemes = get_security_schemes

    security_requirements.each do |security_req|
      security_req.each do |scheme_name, _scopes|
        if security_schemes.key?(scheme_name)
          scheme = security_schemes[scheme_name]
          auth = create_auth_from_scheme(scheme, scheme_name)
          return auth if auth
        end
      end
    end

    nil
  end

  def get_security_schemes
    if @spec.key?('components')
      (@spec.dig('components', 'securitySchemes') || {})
    else
      @spec['securityDefinitions'] || {}
    end
  end

  def create_auth_from_scheme(scheme, _scheme_name)
    scheme_type = (scheme['type'] || '').downcase

    case scheme_type
    when 'apikey'
      location = scheme['in'] || 'header'
      param_name = scheme['name'] || 'Authorization'
      ApiKeyAuth.new(
        api_key: "\${#{@provider_name.upcase}_API_KEY}",
        var_name: param_name,
        location: location
      )
    when 'basic'
      BasicAuth.new(
        username: "\${#{@provider_name.upcase}_USERNAME}",
        password: "\${#{@provider_name.upcase}_PASSWORD}"
      )
    when 'http'
      http_scheme = (scheme['scheme'] || '').downcase
      if http_scheme == 'basic'
        BasicAuth.new(
          username: "\${#{@provider_name.upcase}_USERNAME}",
          password: "\${#{@provider_name.upcase}_PASSWORD}"
        )
      elsif http_scheme == 'bearer'
        ApiKeyAuth.new(
          api_key: "Bearer \${#{@provider_name.upcase}_API_KEY}",
          var_name: 'Authorization',
          location: 'header'
        )
      else
        nil
      end
    when 'oauth2'
      flows = scheme['flows'] || {}
      if flows.any?
        flows.each do |flow_type, flow_config|
          if %w[authorizationCode accessCode clientCredentials application].include?(flow_type)
            token_url = flow_config['tokenUrl']
            if token_url
              scope = (flow_config['scopes'] || {}).keys.join(' ')
              return OAuth2Auth.new(
                token_url: token_url,
                client_id: "\${#{@provider_name.upcase}_CLIENT_ID}",
                client_secret: "\${#{@provider_name.upcase}_CLIENT_SECRET}",
                scope: scope.empty? ? nil : scope
              )
            end
          end
        end
      else
        flow_type = scheme['flow']
        token_url = scheme['tokenUrl']
        if token_url && %w[accessCode application clientCredentials].include?(flow_type)
          scope = (scheme['scopes'] || {}).keys.join(' ')
          return OAuth2Auth.new(
            token_url: token_url,
            client_id: "\${#{@provider_name.upcase}_CLIENT_ID}",
            client_secret: "\${#{@provider_name.upcase}_CLIENT_SECRET}",
            scope: scope.empty? ? nil : scope
          )
        end
      end
      nil
    else
      nil
    end
  end

  def create_t_
