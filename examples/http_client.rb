#!/usr/bin/env ruby
# frozen_string_literal: true

# UTCP client for the HTTP example server.
# Usage:
#   ruby examples/http_client.rb http://127.0.0.1:PORT

require 'utcp'
require 'json'

base = ARGV[0] or abort("Usage: ruby examples/http_client.rb http://127.0.0.1:PORT")
client = Utcp::Client.new
client.register_manual_provider({
  'name' => 'srv',
  'provider_type' => 'http',
  'url' => "#{base}/manual"
})

puts 'HTTP echo ->'
res = client.call_tool('srv.echo', { 'message' => 'hi' })
puts res.inspect

puts 'HTTP stream ->'
client.call_tool('srv.stream') { |chunk| puts "  #{chunk}" }

puts 'SSE stream ->'
client.call_tool('srv.sse') { |event| puts "  #{event}" }
