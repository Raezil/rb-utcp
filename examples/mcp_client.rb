#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the MCP example server.
# Usage:
#   ruby examples/mcp_client.rb http://127.0.0.1:PORT

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utcp'
require 'json'

base = ARGV[0] or abort("Usage: ruby examples/mcp_client.rb http://127.0.0.1:PORT")
client = Utcp::Client.new
client.register_manual_provider({
  'name' => 'srv',
  'provider_type' => 'mcp',
  'url' => base,
  'discovery_path' => '/manual'
})

res = client.call_tool('srv.hello', { 'name' => 'utcp' })
puts res.inspect
