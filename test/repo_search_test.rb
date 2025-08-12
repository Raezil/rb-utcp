# frozen_string_literal: true
require_relative "test_helper"
require "utcp"

class RepoSearchTest < Minitest::Test
  def test_search_scores
    repo = Utcp::ToolRepository.new
    t1 = Utcp::Tool.new(name: "weather", description: "get weather", inputs: {}, outputs: {}, tags: ["meteo"], provider: {})
    t2 = Utcp::Tool.new(name: "news", description: "get headlines", inputs: {}, outputs: {}, tags: ["rss"], provider: {})
    repo.save_provider_with_tools("demo", [t1, t2])
    search = Utcp::Search.new(repo)
    results = search.search("weather")
    assert_equal "weather", results.first[1].name
  end
end
