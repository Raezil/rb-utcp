# frozen_string_literal: true
require_relative "errors"

module Utcp
  class ToolRepository
    def initialize
      @tools = {}          # full_name => Tool
      @by_provider = {}    # provider_name => [Tool]
    end

    def save_provider_with_tools(provider_name, tools)
      @by_provider[provider_name] = tools
      tools.each do |t|
        @tools["#{provider_name}.#{t.name}"] = t
      end
    end

    def providers
      @by_provider.keys
    end

    def find(full_tool_name)
      @tools[full_tool_name] or raise NotFoundError, "Tool not found: #{full_tool_name}"
    end

    def all_tools
      @tools.values
    end

    def remove_provider(provider_name)
      list = @by_provider.delete(provider_name) || []
      list.each { |t| @tools.delete("#{provider_name}.#{t.name}") }
    end
  end
end
