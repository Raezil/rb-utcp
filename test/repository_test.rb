require_relative 'test_helper'
require 'repository'
require 'models'

class RepositoryTest < Minitest::Test
  def setup
    @repo = InMemToolRepository.new
    @provider = TextProvider.new(name: 'p', file_path: 'f.txt')
    @tool = Tool.new(name: 'p.t', description: 'd')
  end

  def test_save_and_get_provider
    @repo.save_provider_with_tools(@provider, [@tool])
    assert_equal @provider, @repo.get_provider('p')
    assert_equal [@tool], @repo.get_tools_by_provider('p')
    assert_equal @tool, @repo.get_tool('p.t')
  end

  def test_remove_tool_and_provider
    @repo.save_provider_with_tools(@provider, [@tool])
    @repo.remove_tool('p.t')
    assert_nil @repo.get_tool('p.t')
    @repo.remove_provider('p')
    assert_nil @repo.get_provider('p')
  end
end
