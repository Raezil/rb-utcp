#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the UDP echo server.
# Usage:
#   ruby examples/udp/client.rb PORT

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

port = Integer(ARGV[0]) rescue abort("Usage: ruby examples/udp/client.rb PORT")
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['port'] = port
  tool = Utcp::Tool.new(
    name: 'echo',
    description: 'udp echo',
    inputs: { 'type' => 'object', 'properties' => { 'msg' => { 'type' => 'string' } } },
    outputs: { 'type' => 'string' },
    tags: [],
    provider: p
  )
  client.repo.save_provider_with_tools(p['name'], [tool])
end

res = client.call_tool('udp.echo', { 'msg' => 'hello' })
puts "UDP response: #{res.inspect}"

