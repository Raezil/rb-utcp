require_relative 'test_helper'

class StreamableTransportTest < Minitest::Test
  def test_build_url_with_path_params
    t = StreamableHttpClientTransport.new(logger: ->(_){})
    url = t.build_url_with_path_params('http://localhost/{id}/file', { id: 5 })
    assert_equal 'http://localhost/5/file', url
    assert_raises(ArgumentError) { t.build_url_with_path_params('x/{id}/{missing}', { id:1 }) }
  end
end
