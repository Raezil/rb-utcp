#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the GraphQL example server.
# Usage:
#   ruby examples/graphql/client.rb http://127.0.0.1:PORT/graphql

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

url = ARGV[0] or abort("Usage: ruby examples/graphql/client.rb http://127.0.0.1:PORT/graphql")
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['url'] = url
  tool = Utcp::Tool.new(
    name: 'greet',
    description: 'graphql greeting',
    inputs: { 'type' => 'object', 'properties' => { 'name' => { 'type' => 'string' } } },
    outputs: { 'type' => 'object' },
    tags: [],
    provider: p
  )
  client.repo.save_provider_with_tools(p['name'], [tool])
end

res = client.call_tool('gql.greet', { 'name' => 'utcp' })
puts res.inspect

