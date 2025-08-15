#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the TCP echo server.
# Usage:
#   ruby examples/tcp/client.rb PORT

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

port = Integer(ARGV[0]) rescue abort("Usage: ruby examples/tcp/client.rb PORT")
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['port'] = port
  tool = Utcp::Tool.new(
    name: 'echo',
    description: 'tcp echo',
    inputs: { 'type' => 'object', 'properties' => { 'msg' => { 'type' => 'string' } } },
    outputs: { 'type' => 'string' },
    tags: [],
    provider: p
  )
  client.repo.save_provider_with_tools(p['name'], [tool])
end

res = client.call_tool('tcp.echo', { 'msg' => 'hello' })
puts "TCP response: #{res.inspect}"

