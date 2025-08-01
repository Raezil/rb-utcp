require_relative 'test_helper'
require 'graphql_transport'
require 'json'

class GraphQLTransportTest < Minitest::Test
  class DummyHTTP
    Response = Struct.new(:body) do
      def code; '200'; end
      def is_a?(klass); klass == Net::HTTPSuccess; end
    end
    def initialize(host, port); end
    def use_ssl=(flag); end
    def request(req)
      Response.new({ access_token: 't' }.to_json)
    end
  end

  def test_handle_oauth2
    transport = GraphQLClientTransport.new(logger: ->(_){})
    auth = OAuth2Auth.new(token_url: 'https://example.com', client_id: 'id', client_secret: 'sec')
    Net::HTTP.stub(:new, DummyHTTP.new('h', 1)) do
      token = transport.handle_oauth2(auth)
      assert_equal 't', token
    end
  end

  def test_enforce_https_or_localhost
    t = GraphQLClientTransport.new(logger: ->(_){})
    assert_raises(ArgumentError) { t.enforce_https_or_localhost!('http://example.com') }
    assert_nil t.enforce_https_or_localhost!('https://example.com')
  end
end
