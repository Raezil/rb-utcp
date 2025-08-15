#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal HTTP server demonstrating UTCP HTTP (including chunked streaming) and SSE providers.
# Run with:
#   ruby examples/http/server.rb
# The server prints its base URL on startup and exposes the following endpoints:
#   /manual - UTCP manual with tool definitions
#   /call   - echo tool using HTTP POST
#   /stream - emits JSON chunks
#   /sse    - emits Server-Sent Events

require 'webrick'
require 'json'

manual = {
  'version' => '1.0',
  'tools' => [
    {
      'name' => 'echo',
      'description' => 'echo arguments',
      'inputs' => { 'type' => 'object' },
      'outputs' => { 'type' => 'object' },
      'tool_provider' => {
        'provider_type' => 'http',
        'url' => nil, # filled after server starts
        'http_method' => 'POST',
        'content_type' => 'application/json'
      }
    },
    {
      'name' => 'stream',
      'description' => 'chunked stream',
      'inputs' => { 'type' => 'object' },
      'outputs' => { 'type' => 'string' },
      'tool_provider' => {
        'provider_type' => 'http',
        'url' => nil
      }
    },
    {
      'name' => 'sse',
      'description' => 'server sent events',
      'inputs' => { 'type' => 'object' },
      'outputs' => { 'type' => 'string' },
      'tool_provider' => {
        'provider_type' => 'sse',
        'url' => nil
      }
    }
  ]
}

server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::ERROR))
port = server.config[:Port]
base = "http://127.0.0.1:#{port}"
manual['tools'][0]['tool_provider']['url'] = base + '/call'
manual['tools'][1]['tool_provider']['url'] = base + '/stream'
manual['tools'][2]['tool_provider']['url'] = base + '/sse'

server.mount_proc '/manual' do |_req, res|
  res['Content-Type'] = 'application/json'
  res.body = JSON.dump(manual)
end

server.mount_proc '/call' do |req, res|
  data = JSON.parse(req.body) rescue {}
  res['Content-Type'] = 'application/json'
  res.body = JSON.dump({ 'ok' => true, 'echo' => data })
end

server.mount_proc '/stream' do |_req, res|
  res['Content-Type'] = 'application/json'
  res.chunked = true
  res.body = Enumerator.new do |y|
    [{ 'a' => 1 }, { 'b' => 2 }, { 'c' => 3 }].each do |obj|
      y << JSON.dump(obj)
      sleep 0.2
    end
  end
end

server.mount_proc '/sse' do |_req, res|
  res['Content-Type'] = 'text/event-stream'
  res.chunked = true
  res.body = Enumerator.new do |y|
    3.times do |i|
      y << "data: event-#{i}\n\n"
      sleep 0.2
    end
  end
end

trap('INT') { server.shutdown }
puts "HTTP provider example listening at #{base}"
puts "Manual: #{base}/manual"
server.start
