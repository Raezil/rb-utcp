#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the GraphQL example server.
# Usage:
#   ruby examples/graphql_client.rb http://127.0.0.1:PORT/graphql

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utcp'

url = ARGV[0] or abort("Usage: ruby examples/graphql_client.rb http://127.0.0.1:PORT/graphql")
client = Utcp::Client.new

tool = Utcp::Tool.new(
  name: 'greet',
  description: 'graphql greeting',
  inputs: { 'type' => 'object', 'properties' => { 'name' => { 'type' => 'string' } } },
  outputs: { 'type' => 'object' },
  tags: [],
  provider: {
    'provider_type' => 'graphql',
    'url' => url,
    'query' => 'query($name:String!){ greeting(name:$name) }'
  }
)
client.repo.save_provider_with_tools('gql', [tool])

res = client.call_tool('gql.greet', { 'name' => 'utcp' })
puts res.inspect
