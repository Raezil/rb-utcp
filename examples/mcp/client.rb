#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the MCP example server.
# Usage:
#   ruby examples/mcp/client.rb http://127.0.0.1:PORT

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

base = ARGV[0] or abort("Usage: ruby examples/mcp/client.rb http://127.0.0.1:PORT")
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['url'] = base
  client.register_manual_provider(p)
end

res = client.call_tool('srv.hello', { 'name' => 'utcp' })
puts res.inspect

