#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the TCP echo server.
# Usage:
#   ruby examples/tcp_client.rb PORT

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utcp'

port = Integer(ARGV[0]) rescue abort("Usage: ruby examples/tcp_client.rb PORT")
client = Utcp::Client.new

tool = Utcp::Tool.new(
  name: 'echo',
  description: 'tcp echo',
  inputs: { 'type' => 'object', 'properties' => { 'msg' => { 'type' => 'string' } } },
  outputs: { 'type' => 'string' },
  tags: [],
  provider: {
    'provider_type' => 'tcp',
    'host' => '127.0.0.1',
    'port' => port,
    'message_template' => '${msg}\n',
    'read_until' => "\n"
  }
)
client.repo.save_provider_with_tools('tcp', [tool])

res = client.call_tool('tcp.echo', { 'msg' => 'hello' })
puts "TCP response: #{res.inspect}"
