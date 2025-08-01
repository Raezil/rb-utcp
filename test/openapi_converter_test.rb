require_relative 'test_helper'
require 'openapi_converter'

class OpenApiConverterTest < Minitest::Test
  def test_convert_paths
    spec = {
      'paths' => {
        '/ping' => {
          'get' => { 'description' => 'ping endpoint', 'tags' => ['health'] }
        }
      }
    }
    conv = OpenApiConverter.new(spec)
    manual = conv.convert
    assert_equal 1, manual.tools.size
    tool = manual.tools.first
    assert_equal 'get__ping', tool.name
    assert_equal ['health'], tool.tags
  end
end
