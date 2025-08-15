#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the HTTP example server.
# Usage:
#   ruby examples/http/client.rb http://127.0.0.1:PORT

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

base = ARGV[0] or abort("Usage: ruby examples/http/client.rb http://127.0.0.1:PORT")
base = base.sub(/\/manual$/, '')
providers = JSON.parse(File.read(File.join(__dir__, 'providers.json')))
client = Utcp::Client.new
providers.each do |p|
  p['url'] = base + p['url']
  client.register_manual_provider(p)
end

puts 'HTTP echo ->'
res = client.call_tool('srv.echo', { 'message' => 'hi' })
puts res.inspect

puts 'HTTP stream ->'
client.call_tool('srv.stream', {}, stream: true) do |chunk|
  puts "  #{JSON.parse(chunk).inspect}" rescue puts("  #{chunk}")
end

puts 'SSE stream ->'
client.call_tool('srv.sse', stream: true) { |event| puts "  #{event}" }

