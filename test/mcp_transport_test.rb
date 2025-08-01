require_relative 'test_helper'
require 'ostruct'

module Async; class Task; def self.current; new; end; def perform; yield; end; end; end
require 'faraday'
require 'mcp_transport'

class MCPTransportTest < Minitest::Test
  def test_parse_text_content
    t = MCPTransport.new(logger: ->(_){})
    assert_equal({'a'=>'b'}, t.send(:parse_text_content, '{"a":"b"}'))
    assert_equal 5, t.send(:parse_text_content, '5')
    assert_equal 2.5, t.send(:parse_text_content, '2.5')
    assert_equal 'x', t.send(:parse_text_content, 'x')
  end
end
