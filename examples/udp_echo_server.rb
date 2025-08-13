#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple UDP echo server for the UTCP UDP provider.
# Run with:
#   ruby examples/udp_echo_server.rb

require 'socket'

sock = UDPSocket.new
sock.bind('127.0.0.1', 0)
port = sock.addr[1]
puts "UDP echo server listening on 127.0.0.1:#{port}"
trap('INT') { sock.close; exit }

loop do
  data, addr = sock.recvfrom(2048)
  sock.send(data, 0, addr[3], addr[1])
end
