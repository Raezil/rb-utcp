# frozen_string_literal: true
require "socket"
port = (ARGV[0] || "5002").to_i
udp = UDPSocket.new
udp.bind("127.0.0.1", port)
puts "UDP echo server on 127.0.0.1:#{port} (Ctrl+C to stop)"
loop do
  data, addr = udp.recvfrom(2048)
  udp.send(data, 0, addr[3], addr[1]) rescue nil
end
