#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple TCP echo server for the UTCP TCP provider.
# Run with:
#   ruby examples/tcp/server.rb

require 'socket'

server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
puts "TCP echo server listening on 127.0.0.1:#{port}"
trap('INT') { server.close; exit }

loop do
  sock = server.accept
  Thread.new(sock) do |s|
    begin
      while (line = s.gets)
        s.write(line)
      end
    ensure
      s.close
    end
  end
end
