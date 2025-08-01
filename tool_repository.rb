# frozen_string_literal: true

# Assumes Provider and Tool are defined elsewhere, e.g.:
# class Provider; end
# class Tool; end

class ToolRepository
  # Save a provider and its tools in the repository.
  #
  # @param provider [Provider] the provider to save.
  # @param tools [Array<Tool>] the tools associated with the provider.
  # @return [void]
  def save_provider_with_tools(provider, tools)
    raise NotImplementedError, "#{self.class} must implement #save_provider_with_tools"
  end

  # Remove a provider and its tools from the repository.
  #
  # @param provider_name [String] the name of the provider to remove.
  # @raise [ArgumentError] if the provider is not found.
  # @return [void]
  def remove_provider(provider_name)
    raise NotImplementedError, "#{self.class} must implement #remove_provider"
  end

  # Remove a tool from the repository.
  #
  # @param tool_name [String] the name of the tool to remove.
  # @raise [ArgumentError] if the tool is not found.
  # @return [void]
  def remove_tool(tool_name)
    raise NotImplementedError, "#{self.class} must implement #remove_tool"
  end

  # Get a tool from the repository.
  #
  # @param tool_name [String] the name of the tool to retrieve.
  # @return [Tool, nil] the tool if found, otherwise nil.
  def get_tool(tool_name)
    raise NotImplementedError, "#{self.class} must implement #get_tool"
  end

  # Get all tools from the repository.
  #
  # @return [Array<Tool>] a list of tools.
  def get_tools
    raise NotImplementedError, "#{self.class} must implement #get_tools"
  end

  # Get tools associated with a specific provider.
  #
  # @param provider_name [String] the name of the provider.
  # @return [Array<Tool>, nil] the list of tools, or nil if provider not found.
  def get_tools_by_provider(provider_name)
    raise NotImplementedError, "#{self.class} must implement #get_tools_by_provider"
  end

  # Get a provider from the repository.
  #
  # @param provider_name [String] the name of the provider to retrieve.
  # @return [Provider, nil] the provider if found, otherwise nil.
  def get_provider(provider_name)
    raise NotImplementedError, "#{self.class} must implement #get_provider"
  end

  # Get all providers from the repository.
  #
  # @return [Array<Provider>] a list of providers.
  def get_providers
    raise NotImplementedError, "#{self.class} must implement #get_providers"
  end
end
