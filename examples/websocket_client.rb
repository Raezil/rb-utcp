#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the WebSocket echo server.
# Usage:
#   ruby examples/websocket_client.rb ws://127.0.0.1:PORT/

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utcp'

url = ARGV[0] or abort("Usage: ruby examples/websocket_client.rb ws://127.0.0.1:PORT/")
client = Utcp::Client.new

tool = Utcp::Tool.new(
  name: 'echo',
  description: 'websocket echo',
  inputs: { 'type' => 'object' },
  outputs: { 'type' => 'string' },
  tags: [],
  provider: { 'provider_type' => 'websocket', 'url' => url }
)
client.repo.save_provider_with_tools('ws', [tool])

res = client.call_tool('ws.echo', { 'msg' => 'hello' })
puts "WebSocket response: #{res.inspect}"
