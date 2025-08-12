# frozen_string_literal: true
require_relative "test_helper"
require "utcp"
include TestUtils

class TransportsMiscTest < Minitest::Test
  def setup
    @echo_tcp = TcpEcho.new
    @echo_udp = UdpEcho.new
  end

  def teardown
    @echo_tcp.shutdown
    @echo_udp.shutdown
  end

  def test_tcp_udp_cli_via_text_manual
    manual = {
      "version"=>"1.0",
      "tools"=>[
        {
          "name"=>"tcp_echo",
          "description"=>"tcp echo",
          "inputs"=>{ "type"=>"object" },
          "outputs"=>{ "type"=>"string" },
          "tool_provider"=>{
            "provider_type"=>"tcp",
            "host"=>"127.0.0.1",
            "port"=> @echo_tcp.port,
            "message_template"=>"hello ${name}\n",
            "read_until"=>"\n",
            "timeout_ms"=> 1000
          }
        },
        {
          "name"=>"udp_ping",
          "description"=>"udp echo",
          "inputs"=>{ "type"=>"object" },
          "outputs"=>{ "type"=>"string" },
          "tool_provider"=>{
            "provider_type"=>"udp",
            "host"=>"127.0.0.1",
            "port"=> @echo_udp.port,
            "message_template"=>"ping ${who}",
            "timeout_ms"=> 1000,
            "max_bytes"=> 2048
          }
        },
        {
          "name"=>"shell_echo",
          "description"=>"cli echo",
          "inputs"=>{ "type"=>"object" },
          "outputs"=>{ "type"=>"object" },
          "tool_provider"=>{
            "provider_type"=>"cli",
            "command"=> ["/bin/echo", "Message: ${msg}"]
          }
        }
      ]
    }

    with_tmpdir do |dir|
      manual_path = File.join(dir, "manual.json")
      File.write(manual_path, JSON.dump(manual))
      providers = [
        { "name"=>"sock_demo", "provider_type"=>"text", "file_path"=> manual_path }
      ]
      pfile = File.join(dir, "providers.json")
      File.write(pfile, JSON.dump(providers))

      client = Utcp::Client.create({ "providers_file_path" => pfile })

      # TCP
      out = client.call_tool("sock_demo.tcp_echo", { "name"=>"kamil" }).to_s
      assert_includes out, "hello kamil"

      # UDP
      out2 = client.call_tool("sock_demo.udp_ping", { "who"=>"ws" }).to_s
      assert_includes out2, "ping ws"

      # CLI
      res = client.call_tool("sock_demo.shell_echo", { "msg"=>"hi" })
      assert res["ok"]
      assert_includes res["stdout"], "Message: hi"
    end
  end
end
