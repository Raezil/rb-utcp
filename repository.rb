class InMemToolRepository
  def initialize
    @tools = []
    # map provider_name => [provider, [tools]]
    @tool_per_provider = {}
  end

  # @param provider [Provider]
  # @param tools [Array<Tool>]
  def save_provider_with_tools(provider, tools)
    @tools.concat(tools)
    @tool_per_provider[provider.name] = [provider, tools]
    nil
  end

  # @param provider_name [String]
  def remove_provider(provider_name)
    unless @tool_per_provider.key?(provider_name)
      raise ArgumentError, "Provider '#{provider_name}' not found"
    end

    tools_to_remove = @tool_per_provider[provider_name][1]
    @tools = @tools.reject { |t| tools_to_remove.include?(t) }
    @tool_per_provider.delete(provider_name)
    nil
  end

  # @param tool_name [String]
  def remove_tool(tool_name)
    provider_name = tool_name.split('.', 2).first
    unless @tool_per_provider.key?(provider_name)
      raise ArgumentError, "Provider '#{provider_name}' not found"
    end

    before_count = @tools.size
    @tools = @tools.reject { |t| t.name == tool_name }
    if @tools.size == before_count
      raise ArgumentError, "Tool '#{tool_name}' not found"
    end

    provider, provider_tools = @tool_per_provider[provider_name]
    updated_tools = provider_tools.reject { |t| t.name == tool_name }
    @tool_per_provider[provider_name] = [provider, updated_tools]
    nil
  end

  # @param tool_name [String]
  # @return [Tool, nil]
  def get_tool(tool_name)
    @tools.find { |t| t.name == tool_name }
  end

  # @return [Array<Tool>]
  def get_tools
    @tools
  end

  # @param provider_name [String]
  # @return [Array<Tool>, nil]
  def get_tools_by_provider(provider_name)
    entry = @tool_per_provider[provider_name]
    entry ? entry[1] : nil
  end

  # @param provider_name [String]
  # @return [Provider, nil]
  def get_provider(provider_name)
    entry = @tool_per_provider[provider_name]
    entry ? entry[0] : nil
  end

  # @return [Array<Provider>]
  def get_providers
    @tool_per_provider.values.map { |provider, _| provider }
  end
end
