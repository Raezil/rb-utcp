require 'json'
require 'pathname'
require 'async'

# Custom error types
class UtcpVariableNotFound < StandardError; end

# Interface (module with required methods)
module UtcpClientInterface
  def register_tool_provider(manual_provider)
    raise NotImplementedError, "#{self.class} must implement register_tool_provider"
  end

  def deregister_tool_provider(provider_name)
    raise NotImplementedError, "#{self.class} must implement deregister_tool_provider"
  end

  def call_tool(tool_name, arguments)
    raise NotImplementedError, "#{self.class} must implement call_tool"
  end

  def search_tools(query, limit = 10)
    raise NotImplementedError, "#{self.class} must implement search_tools"
  end
end

# Placeholder classes / dependencies - you should replace these with real implementations
# class Tool; end
# class ToolRepository; end
# class ToolSearchStrategy; end

# UtcpClient implementation
class UtcpClient
  include UtcpClientInterface

  # Pre-instantiated transports; assume these implement register_tool_provider, call_tool, etc.
  # Replace with your actual transport implementations.
  @@transports = {
    'http' => HttpClientTransport.new,
    'cli' => CliTransport.new,
    'sse' => SSEClientTransport.new,
    'http_stream' => StreamableHttpClientTransport.new,
    'mcp' => MCPTransport.new,
    'text' => TextTransport.new,
    'graphql' => GraphQLClientTransport.new
  }

  attr_reader :tool_repository, :search_strategy, :config
  attr_accessor :transports

  def initialize(config, tool_repository, search_strategy)
    @tool_repository = tool_repository
    @search_strategy = search_strategy
    @config = config
    @transports = @@transports.dup # allow mutation per-instance
  end

  # Async factory
  def self.create(config: nil, tool_repository: nil, search_strategy: nil)
    Async do
      tool_repository ||= InMemToolRepository.new
      search_strategy ||= TagSearchStrategy.new(tool_repository)
      config = if config.nil?
                 UtcpClientConfig.new
               elsif config.is_a?(Hash)
                 UtcpClientConfig.model_validate(config)
               else
                 config
               end

      client = new(config, tool_repository, search_strategy)

      if client.config.providers_file_path && !client.config.providers_file_path.empty?
        providers_dir = File.dirname(File.absolute_path(client.config.providers_file_path))
        client.transports['text'] = TextTransport.new(base_path: providers_dir)
      end

      if client.config.variables
        config_without_vars = client.config.dup
        config_without_vars.variables = nil
        client.config.variables = client._replace_vars_in_obj(client.config.variables, config_without_vars)
      end

      awaitable_providers = client.load_providers(client.config.providers_file_path)
      registered = awaitable_providers.wait
      client
    end
  end

  # Load providers from file, register them in parallel
  def load_providers(providers_file_path)
    Async do
      return [] if providers_file_path.nil? || providers_file_path.empty?

      resolved_path = Pathname.new(providers_file_path).realpath rescue nil
      raise Errno::ENOENT, "Providers file not found: #{providers_file_path}" unless resolved_path && File.exist?(resolved_path)

      begin
        raw = File.read(resolved_path)
        providers_data = JSON.parse(raw)
      rescue JSON::ParserError
        raise ArgumentError, "Invalid JSON in providers file: #{providers_file_path}"
      end

      unless providers_data.is_a?(Array)
        raise ArgumentError, "Providers file must contain a JSON array at the root level: #{providers_file_path}"
      end

      provider_class_map = {
        'http' => HttpProvider,
        'cli' => CliProvider,
        'sse' => SSEProvider,
        'http_stream' => StreamableHttpProvider,
        'websocket' => WebSocketProvider,
        'grpc' => GRPCProvider,
        'graphql' => GraphQLProvider,
        'tcp' => TCPProvider,
        'udp' => UDPProvider,
        'webrtc' => WebRTCProvider,
        'mcp' => MCPProvider,
        'text' => TextProvider
      }

      tasks = providers_data.map do |provider_data|
        Async do
          begin
            provider_type = provider_data['provider_type']
            unless provider_type
              warn "Warning: Provider entry is missing required 'provider_type' field, skipping: #{provider_data}"
              next nil
            end

            provider_class = provider_class_map[provider_type]
            unless provider_class
              warn "Warning: Unsupported provider type: #{provider_type}, skipping"
              next nil
            end

            provider = provider_class.model_validate(provider_data)
            provider = _substitute_provider_variables(provider)
            tools = register_tool_provider(provider).wait
            puts "Successfully registered provider '#{provider.name}' with #{tools.size} tools"
            provider
          rescue => e
            provider_name = provider_data['name'] || 'unknown'
            warn "Error registering provider '#{provider_name}': #{e.message}"
            nil
          end
        end
      end

      results = tasks.map(&:wait).compact
      results
    end
  end

  # Internal: get variable value, checking config, loaders, env
  def _get_variable(key, config_obj)
    if config_obj.variables && config_obj.variables.key?(key)
      return config_obj.variables[key]
    end

    if config_obj.load_variables_from
      config_obj.load_variables_from.each do |loader|
        var = loader.get(key) if loader.respond_to?(:get)
        return var if var
      end
    end

    env = ENV[key]
    return env if env && !env.empty?

    raise UtcpVariableNotFound, key
  end

  # Recursively replace variables in object (hash, array, string)
  def _replace_vars_in_obj(obj, config_obj)
    case obj
    when Hash
      obj.transform_values { |v| _replace_vars_in_obj(v, config_obj) }
    when Array
      obj.map { |elem| _replace_vars_in_obj(elem, config_obj) }
    when String
      obj.gsub(/\$\{(\w+)\}|\$(\w+)/) do
        var_name = Regexp.last_match(1) || Regexp.last_match(2)
        _get_variable(var_name, config_obj)
      end
    else
      obj
    end
  end

  def _substitute_provider_variables(provider)
    provider_hash = provider.model_dump
    processed = _replace_vars_in_obj(provider_hash, @config)
    provider.class.new(**processed)
  end

  # Register a tool provider (async)
  def register_tool_provider(manual_provider)
    Async do
      manual_provider = _substitute_provider_variables(manual_provider)
      manual_provider.name = manual_provider.name.gsub('.', '_')
      unless transports.key?(manual_provider.provider_type)
        raise ArgumentError, "Provider type not supported: #{manual_provider.provider_type}"
      end

      transport = transports[manual_provider.provider_type]
      tools = transport.register_tool_provider(manual_provider).wait

      tools.each do |tool|
        unless tool.name.start_with?("#{manual_provider.name}.")
          tool.name = "#{manual_provider.name}.#{tool.name}"
        end
      end

      tool_repository.save_provider_with_tools(manual_provider, tools).wait
      tools
    end
  end

  def deregister_tool_provider(provider_name)
    Async do
      provider = tool_repository.get_provider(provider_name).wait
      raise ArgumentError, "Provider not found: #{provider_name}" unless provider

      transports[provider.provider_type].deregister_tool_provider(provider).wait
      tool_repository.remove_provider(provider_name).wait
      nil
    end
  end

  def call_tool(tool_name, arguments)
    Async do
      provider_name = tool_name.split('.').first
      provider = tool_repository.get_provider(provider_name).wait
      raise ArgumentError, "Provider not found: #{provider_name}" unless provider

      tools = tool_repository.get_tools_by_provider(provider_name).wait
      tool = tools.find { |t| t.name == tool_name }
      raise ArgumentError, "Tool not found: #{tool_name}" unless tool

      tool_provider = tool.tool_provider
      tool_provider = _substitute_provider_variables(tool_provider)

      transport = transports[tool_provider.provider_type]
      transport.call_tool(tool_name, arguments, tool_provider).wait
    end
  end

  def search_tools(query, limit = 10)
    Async do
      search_strategy.search_tools(query, limit).wait
    end
  end
end
