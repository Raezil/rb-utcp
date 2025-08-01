require_relative 'test_helper'
require 'sse_transport'

class SSETransportTest < Minitest::Test
  def test_build_url_with_path_params
    t = SSEClientTransport.new(logger: ->(_){})
    url = t.build_url_with_path_params('http://localhost/{id}', { 'id' => '1' })
    assert_equal 'http://localhost/1', url
  end
end
