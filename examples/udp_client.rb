#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the UDP echo server.
# Usage:
#   ruby examples/udp_client.rb PORT

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utcp'

port = Integer(ARGV[0]) rescue abort("Usage: ruby examples/udp_client.rb PORT")
client = Utcp::Client.new

tool = Utcp::Tool.new(
  name: 'echo',
  description: 'udp echo',
  inputs: { 'type' => 'object', 'properties' => { 'msg' => { 'type' => 'string' } } },
  outputs: { 'type' => 'string' },
  tags: [],
  provider: {
    'provider_type' => 'udp',
    'host' => '127.0.0.1',
    'port' => port,
    'message_template' => '${msg}'
  }
)
client.repo.save_provider_with_tools('udp', [tool])

res = client.call_tool('udp.echo', { 'msg' => 'hello' })
puts "UDP response: #{res.inspect}"
