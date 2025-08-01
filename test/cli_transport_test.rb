require_relative 'test_helper'
require 'cli_transport'
require 'models'

class CliTransportTest < Minitest::Test
  def setup
    @transport = CliTransport.new(logger: ->(_msg) {})
  end

  def test_format_arguments
    args = { msg: 'hi', flag: true, skip: false, list: [1,2] }
    formatted = @transport.send(:format_arguments, args)
    assert_equal ['--msg','hi','--flag','--list','1','--list','2'], formatted
  end

  def test_extract_utcp_manual_from_output
    output = { tools: [ { name: 't', description: 'd' } ] }.to_json
    tools = @transport.send(:extract_utcp_manual_from_output, output, 'prov')
    assert_equal 1, tools.size
    assert_equal 't', tools.first.name
  end
end
