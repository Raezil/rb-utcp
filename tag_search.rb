require 'set'
require_relative 'tool_search_strategy'

class TagSearchStrategy < ToolSearchStrategy
  def initialize(tool_repository, description_weight: 0.3)
    @tool_repository = tool_repository
    # Weight for description words vs explicit tags (explicit tags have weight of 1.0)
    @description_weight = description_weight
  end

  # @param query [String]
  # @param limit [Integer]
  # @return [Array<Tool>]
  def normalized_downcase(str)
    str.to_s.unicode_normalize(:nfc).downcase
  end

  def search_tools(query, limit: 10)
    query_lower = normalized_downcase(query)

    query_words = Set.new(query_lower.scan(/\w+/))

    tools = @tool_repository.get_tools

    tool_scores = []

    tools.each do |tool|
      score = 0.0

      # Score from explicit tags (weight 1.0)
      tool.tags.each do |tag|
        tag_lower = tag.downcase

        # Full-tag match in query string
        if query_lower.include?(tag_lower)
          score += 1.0
        end

        # Partial/tag-word matches
        tag_words = Set.new(tag_lower.scan(/\w+/))
        tag_words.each do |word|
          if query_words.include?(word)
            score += @description_weight
          end
        end
      end

      # Score from description (with lower weight)
      if tool.description
        description_words = Set.new(tool.description.downcase.scan(/\w+/))
        description_words.each do |word|
          next if word.length <= 2
          if query_words.include?(word)
            score += @description_weight
          end
        end
      end

      tool_scores << [tool, score]
    end

    # Sort descending by score and take top `limit`
    sorted = tool_scores.sort_by { |_, score| -score }.map(&:first)
    sorted.first(limit)
  end
end
