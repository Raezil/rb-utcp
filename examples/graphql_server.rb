#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal GraphQL HTTP server for the UTCP GraphQL provider.
# It ignores the query and simply returns a greeting using variables.
# Run with:
#   ruby examples/graphql_server.rb

require 'webrick'
require 'json'

class GraphQLServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(req, res)
    data = JSON.parse(req.body) rescue {}
    name = data.dig('variables', 'name') || 'world'
    res['Content-Type'] = 'application/json'
    res.body = JSON.dump({ 'data' => { 'greeting' => "hello #{name}" } })
  end
end

server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::ERROR))
server.mount '/graphql', GraphQLServlet
port = server.config[:Port]
puts "GraphQL example listening at http://127.0.0.1:#{port}/graphql"
trap('INT') { server.shutdown }
server.start
