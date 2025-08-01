require 'uri'
require_relative 'models'

# Minimal OpenAPI to UTCP manual converter.
class OpenApiConverter
  def initialize(openapi_spec, spec_url: nil, provider_name: nil)
    @spec = openapi_spec
    @spec_url = spec_url
    @provider_name = provider_name || 'openapi_provider'
  end

  def convert
    tools = []
    paths = @spec['paths'] || {}
    paths.each do |path, methods|
      methods.each do |method, op|
        next unless %w[get post put delete patch].include?(method.to_s.downcase)
        name = "#{method}_#{path.gsub(/[^a-zA-Z0-9]/, '_')}"
        description = op['description'] || ''
        tags = op['tags'] || []
        tools << Tool.new(name: name, description: description, tags: tags)
      end
    end
    UtcpManual.new(tools: tools)
  end
end
