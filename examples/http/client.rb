#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the HTTP example server.
# Usage:
#   ruby examples/http/client.rb http://127.0.0.1:PORT

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'utcp'
require 'json'

base = ARGV[0] or abort("Usage: ruby examples/http/client.rb http://127.0.0.1:PORT")
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
client.call_tool('srv.stream', {}, stream: true) { |chunk| puts "  #{chunk}" }

puts 'SSE stream ->'
client.call_tool('srv.sse') { |event| puts "  #{event}" }

