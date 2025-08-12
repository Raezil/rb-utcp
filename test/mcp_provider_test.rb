# frozen_string_literal: true
require_relative "test_helper"
require "utcp"
include TestUtils

class McpProviderTest < Minitest::Test
  def setup
    @servers = []
  end

  def teardown
    @servers.each(&:shutdown)
  end

  def test_mcp_manual_and_call
    mcp_base = nil
    manual_body = {
      "version"=>"1.0",
      "tools"=>[
        {
          "name"=>"hello",
          "description"=>"say hello",
          "inputs"=>{ "type"=>"object" },
          "outputs"=>{ "type"=>"object" },
          "tool_provider"=>{
            "provider_type"=>"mcp",
            "url"=> nil, # fill
            "call_path"=>"/call"
          }
        }
      ]
    }

    server = MiniHTTPServer.new({
      ["GET", "/mcp/manual"] => ->(req) { [200, { "Content-Type"=>"application/json" }, JSON.dump(manual_body)] },
      ["POST", "/mcp/call"] => ->(req) {
        data = JSON.parse(req[:body]) rescue {}
        out = { "tool"=> data["tool"], "arguments"=> data["arguments"], "greeting"=>"hello #{data.dig("arguments", "name")}" }
        [200, { "Content-Type"=>"application/json" }, JSON.dump(out)]
      }
    })
    @servers << server
    mcp_base = "http://127.0.0.1:%d/mcp" % server.port
    manual_body["tools"][0]["tool_provider"]["url"] = mcp_base

    with_tmpdir do |dir|
      providers = [
        { "name"=>"mcp_demo", "provider_type"=>"mcp", "url"=> mcp_base, "discovery_path"=>"/manual" }
      ]
      pfile = File.join(dir, "providers.json")
      File.write(pfile, JSON.dump(providers))

      client = Utcp::Client.create({ "providers_file_path" => pfile })
      res = client.call_tool("mcp_demo.hello", { "name"=>"Kamil" })
      assert_equal "hello Kamil", res["greeting"]
      assert_equal "hello", res["tool"]
    end
  end
end
