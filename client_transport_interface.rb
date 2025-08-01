# frozen_string_literal: true

class ClientTransportInterface
  # @param manual_provider [Provider]
  # @return [Array<Tool>]
  def register_tool_provider(manual_provider)
    raise NotImplementedError, "Subclasses must implement #register_tool_provider"
  end

  # @param manual_provider [Provider]
  # @return [void]
  def deregister_tool_provider(manual_provider)
    raise NotImplementedError, "Subclasses must implement #deregister_tool_provider"
  end

  # @param tool_name [String]
  # @param arguments [Hash]
  # @param tool_provider [Provider]
  # @return [Object] result of calling the tool
  def call_tool(tool_name, arguments, tool_provider)
    raise NotImplementedError, "Subclasses must implement #call_tool"
  end
end
