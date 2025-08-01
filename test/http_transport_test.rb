require_relative 'test_helper'
require 'http_transport'

class HttpTransportTest < Minitest::Test
  def setup
    @transport = HttpClientTransport.new(logger: ->(_msg, **_){})
  end

  def test_enforce_https_or_localhost
    assert_raises(ArgumentError) { @transport.send(:enforce_https_or_localhost!, 'http://bad.com') }
    assert_nil @transport.send(:enforce_https_or_localhost!, 'https://good.com')
  end

  def test_build_url_with_path_params
    url = @transport.send(:build_url_with_path_params, 'https://x/{id}', { 'id' => 1 })
    assert_equal 'https://x/1', url
  end

  def test_apply_auth_api_key_header
    provider = HttpProvider.new(name: 'p', url: 'http://localhost', http_method: 'GET', auth: ApiKeyAuth.new(api_key: 'k', var_name: 'X-Api-Key'))
    headers = {}
    query = {}
    _auth, cookies = @transport.send(:apply_auth, provider, headers, query)
    assert_equal 'k', headers['X-Api-Key']
    assert_empty cookies
  end
end
