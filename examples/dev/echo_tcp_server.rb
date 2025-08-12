# frozen_string_literal: true
require "socket"
port = (ARGV[0] || "5001").to_i
server = TCPServer.new("127.0.0.1", port)
puts "TCP echo server on 127.0.0.1:#{port} (Ctrl+C to stop)"
loop do
  sock = server.accept
  Thread.new(sock) do |s|
    begin
      while (line = s.gets)
        s.write(line)
      end
    rescue
    ensure
      s.close rescue nil
    end
  end
end
