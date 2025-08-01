# frozen_string_literal: true

# Assumes Tool is defined elsewhere, e.g.:
# class Tool; end

class ToolSearchStrategy
  # Search for tools relevant to the query.
  #
  # @param query [String] the search query.
  # @param limit [Integer] the maximum number of tools to return. 0 for no limit.
  # @return [Array<Tool>] a list of tools that match the search query.
  def search_tools(query, limit: 10)
    raise NotImplementedError, "#{self.class} must implement #search_tools"
  end
end
