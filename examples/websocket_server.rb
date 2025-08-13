#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal WebSocket echo server for the UTCP WebSocket provider.
# Run with:
#   ruby examples/websocket_server.rb
# The server prints its ws:// URL and echoes the first text frame it receives.

require 'socket'
require 'digest/sha1'
require 'base64'

GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
puts "WebSocket example listening at ws://127.0.0.1:#{port}/"
trap('INT') { server.close; exit }

loop do
  sock = server.accept
  Thread.new(sock) do |s|
    # Read HTTP handshake
    request = ""
    while (line = s.gets)
      request << line
      break if line == "\r\n"
    end
    key = request[/Sec-WebSocket-Key: (.*)\r\n/, 1]
    accept = Base64.strict_encode64(Digest::SHA1.digest(key + GUID))
    headers = [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      "Sec-WebSocket-Accept: #{accept}",
      '', ''
    ].join("\r\n")
    s.write(headers)

    # Read one text frame from client
    h = s.read(2)&.bytes
    next unless h
    b1, b2 = h
    len = b2 & 0x7f
    len = s.read(2).unpack('n')[0] if len == 126
    len = s.read(8).unpack('Q>')[0] if len == 127
    mask = s.read(4)
    payload = s.read(len) || ''
    data = payload.bytes.each_with_index.map { |b, i| (b ^ mask.getbyte(i % 4)) }.pack('C*')

    # Echo back
    msg = "echo: #{data}"
    frame = [0x81].pack('C') # FIN + text
    if msg.bytesize < 126
      frame << msg.bytesize.chr
    elsif msg.bytesize < 65_536
      frame << [126, msg.bytesize].pack('Cn')
    else
      frame << [127, msg.bytesize].pack('CQ>')
    end
    s.write(frame + msg)
    s.close
  end
end
