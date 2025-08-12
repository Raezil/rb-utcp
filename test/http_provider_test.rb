# frozen_string_literal: true
require_relative "test_helper"
require "utcp"
include TestUtils

class HttpProviderTest < Minitest::Test
  def setup
    @servers = []
  end

  def teardown
    @servers.each(&:shutdown)
  end

  def test_http_manual_and_call
    manual = {
      "version" => "1.0",
      "tools" => [
        {
          "name" => "echo",
          "description" => "echo",
          "inputs" => { "type"=>"object" },
          "outputs" => { "type"=>"object" },
          "tool_provider" => {
            "provider_type" => "http",
            "url" => nil, # will fill later with local base + /call
            "http_method" => "POST",
            "content_type" => "application/json"
          }
        },
        {
          "name" => "stream",
          "description" => "stream",
          "inputs" => { "type"=>"object" },
          "outputs" => { "type"=>"string" },
          "tool_provider" => {
            "provider_type" => "http_stream",
            "url" => nil # fill with /stream
          }
        },
        {
          "name" => "sse",
          "description" => "sse",
          "inputs" => { "type"=>"object" },
          "outputs" => { "type"=>"string" },
          "tool_provider" => {
            "provider_type" => "sse",
            "url" => nil # fill with /sse
          }
        }
      ]
    }

    # Start local http server
    server = MiniHTTPServer.new({
      ["GET", "/manual"] => ->(req) { [200, { "Content-Type"=>"application/json" }, JSON.dump(@manual_body)] },
      ["POST", "/call"] => ->(req) {
        data = JSON.parse(req[:body]) rescue {}
        [200, { "Content-Type"=>"application/json" }, JSON.dump({ "ok"=>true, "echo"=>data })]
      },
      ["GET", "/sse"] => ->(req) { :sse },
      ["GET", "/stream"] => ->(req) { :chunk }
    })
    @servers << server
    base = "http://127.0.0.1:#{server.port}"
    # fill manual with real URLs
    manual["tools"][0]["tool_provider"]["url"] = base + "/call"
    manual["tools"][1]["tool_provider"]["url"] = base + "/stream"
    manual["tools"][2]["tool_provider"]["url"] = base + "/sse"
    @manual_body = manual

    with_tmpdir do |dir|
      providers = [
        { "name"=>"demo", "provider_type"=>"http", "url"=> base + "/manual", "http_method"=>"GET" }
      ]
      pfile = File.join(dir, "providers.json")
      File.write(pfile, JSON.dump(providers))

      client = Utcp::Client.create({ "providers_file_path" => pfile })
      assert_includes client.repo.providers, "demo"

      res = client.call_tool("demo.echo", { "x"=>1 })
      assert_equal true, res["ok"]
      assert_equal({ "x"=>1 }, res["echo"])

      chunks = []
      client.call_tool("demo.stream", {}, stream: true) { |c| chunks << c }
      refute_empty chunks

      sse = []
      client.call_tool("demo.sse", {}, stream: true) { |ev| sse << ev }
      assert_equal 3, sse.size
    end
  end
end
