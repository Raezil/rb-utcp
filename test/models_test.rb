require_relative 'test_helper'
require 'models'

class ModelsTest < Minitest::Test
  def test_tool_model_validate
    tool_hash = { 'name' => 'echo', 'description' => 'echo tool', 'tags' => ['test'] }
    tool = Tool.model_validate(tool_hash)
    assert_equal 'echo', tool.name
    assert_equal ['test'], tool.tags
  end

  def test_manual_model_validate
    hash = { tools: [ { name: 't', description: 'd' } ] }
    manual = UtcpManual.model_validate(hash)
    assert_equal 1, manual.tools.size
    assert_equal 't', manual.tools.first.name
  end

  def test_api_key_auth_init
    auth = ApiKeyAuth.new(api_key: 'k', var_name: 'X')
    assert_equal 'k', auth.api_key
    assert_equal 'X', auth.var_name
  end

  def test_http_provider
    prov = HttpProvider.new(name: 'p', url: 'http://localhost', http_method: 'GET')
    assert_equal 'http', prov.provider_type
  end

  def test_graphql_provider
    prov = GraphQLProvider.new(name: 'g')
    assert_equal 'graphql', prov.provider_type
  end
end
