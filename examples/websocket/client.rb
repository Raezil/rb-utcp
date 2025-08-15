#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the WebSocket echo server.
# Usage:
#   ruby examples/websocket/client.rb ws://127.0.0.1:PORT/

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

url = ARGV[0] or abort("Usage: ruby examples/websocket/client.rb ws://127.0.0.1:PORT/")
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['url'] = url
  tool = Utcp::Tool.new(
    name: 'echo',
    description: 'websocket echo',
    inputs: { 'type' => 'object' },
    outputs: { 'type' => 'string' },
    tags: [],
    provider: p
  )
  client.repo.save_provider_with_tools(p['name'], [tool])
end

res = client.call_tool('ws.echo', { 'msg' => 'hello' })
puts "WebSocket response: #{res.inspect}"

