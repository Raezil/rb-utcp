require_relative 'test_helper'
require 'tag_search'
require 'repository'
require 'models'

class TagSearchTest < Minitest::Test
  def test_search_by_tags_and_description
    repo = InMemToolRepository.new
    tool1 = Tool.new(name: 'a', description: 'first', tags: ['alpha'])
    tool2 = Tool.new(name: 'b', description: 'second tool', tags: ['beta'])
    repo.save_provider_with_tools(TextProvider.new(name: 'p', file_path: 'f'), [tool1, tool2])
    searcher = TagSearchStrategy.new(repo)
    results = searcher.search_tools('alpha')
    assert_includes results.map(&:name), 'a'
    results = searcher.search_tools('second')
    assert_includes results.map(&:name), 'b'
  end
end
