require_relative 'test_helper'
require 'tempfile'
require 'text_transport'
require 'models'

class TextTransportTest < Minitest::Test
  def with_temp_manual(content)
    file = Tempfile.new(['tool', '.json'])
    file.write(content)
    file.close
    yield file.path
  ensure
    file.unlink if file
  end

  def test_register_tool_provider_from_manual
    manual_json = { tools: [ { name: 'echo', description: 'd' } ] }.to_json
    with_temp_manual(manual_json) do |path|
      provider = TextProvider.new(name: 'p', file_path: path)
      transport = TextTransport.new
      tools = transport.register_tool_provider(provider)
      assert_equal 1, tools.size
      assert_equal 'echo', tools.first.name
    end
  end

  def test_call_tool_reads_file
    with_temp_manual('plain text') do |path|
      provider = TextProvider.new(name: 'p', file_path: path)
      transport = TextTransport.new
      result = transport.call_tool('p.echo', {}, provider)
      assert_equal 'plain text', result
    end
  end
end
