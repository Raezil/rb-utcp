#!/usr/bin/env ruby
# frozen_string_literal: true

# Real GraphQL HTTP server for the UTCP GraphQL provider.
# Run with:
#   gem install graphql
#   ruby examples/graphql/server.rb

require 'webrick'
require 'json'
require 'graphql'

class QueryType < GraphQL::Schema::Object
  field :greeting, String, null: false do
    argument :name, String, required: false
  end

  def greeting(name: 'world')
    "hello #{name}"
  end
end

class ExampleSchema < GraphQL::Schema
  query QueryType
end

class GraphQLServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(req, res)
    data = JSON.parse(req.body) rescue {}
    result = ExampleSchema.execute(
      data['query'],
      variables: data['variables'] || {}
    )
    res['Content-Type'] = 'application/json'
    res.body = JSON.dump(result.to_h)
  end
end

server = WEBrick::HTTPServer.new(
  Port: 0,
  BindAddress: '127.0.0.1',
  AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::ERROR)
)
server.mount '/graphql', GraphQLServlet
port = server.config[:Port]
puts "GraphQL example listening at http://127.0.0.1:#{port}/graphql"
trap('INT') { server.shutdown }
server.start
