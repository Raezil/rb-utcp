#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal MCP server for the UTCP MCP provider.
# Run with:
#   ruby examples/mcp_server.rb

require 'webrick'
require 'json'

manual = {
  'version' => '1.0',
  'tools' => [
    {
      'name' => 'hello',
      'description' => 'say hello',
      'inputs' => { 'type' => 'object' },
      'outputs' => { 'type' => 'object' },
      'tool_provider' => {
        'provider_type' => 'mcp',
        'url' => nil, # filled with server base
        'call_path' => '/call'
      }
    }
  ]
}

server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::ERROR))
port = server.config[:Port]
base = "http://127.0.0.1:#{port}"
manual['tools'][0]['tool_provider']['url'] = base

server.mount_proc '/manual' do |_req, res|
  res['Content-Type'] = 'application/json'
  res.body = JSON.dump(manual)
end

server.mount_proc '/call' do |req, res|
  data = JSON.parse(req.body) rescue {}
  name = data.dig('arguments', 'name')
  out = { 'tool' => data['tool'], 'arguments' => data['arguments'], 'greeting' => "hello #{name}" }
  res['Content-Type'] = 'application/json'
  res.body = JSON.dump(out)
end

trap('INT') { server.shutdown }
puts "MCP provider example listening at #{base}"
puts "Discovery: #{base}/manual"
server.start
