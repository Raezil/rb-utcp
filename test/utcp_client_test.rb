require_relative 'test_helper'
require 'utcp_client'
require 'repository'
require 'tag_search'

class UtcpClientTest < Minitest::Test
  def test_replace_vars_in_obj
    cfg = UtcpClientConfig.new(variables: { 'A' => 'x' })
    client = UtcpClient.new(cfg, InMemToolRepository.new, TagSearchStrategy.new(InMemToolRepository.new))
    obj = { 'v' => '${A}', 'arr' => ['$A'] }
    result = client.send(:_replace_vars_in_obj, obj, cfg)
    assert_equal({'v' => 'x', 'arr' => ['x'] }, result)
  end
end
