# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "socket"
require "json"
require "tempfile"
require "fileutils"

module TestUtils
  def with_tmpdir
    dir = Dir.mktmpdir("ruby-utcp-test")
    begin
      yield dir
    ensure
      FileUtils.remove_entry(dir) if Dir.exist?(dir)
    end
  end

  # Simple local HTTP server for tests (supports GET, POST, SSE, and chunked stream)
  class MiniHTTPServer
    attr_reader :port

    def initialize(responders)
      @responders = responders
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thr = Thread.new { run }
      @thr.report_on_exception = false
    end


    def run
      loop do
        sock = @server.accept
        t = Thread.new(sock) { |s| handle_client(s) }
        t.report_on_exception = false
      end
    rescue IOError, SystemCallError
      # server socket closed during shutdown
    end


    def handle_client(sock)
      request_line = sock.gets("\r\n") || ""
      method, path, _ = request_line.split(" ", 3)
      headers = {}
      while (line = sock.gets("\r\n"))
        line = line.strip
        break if line.empty?
        k, v = line.split(":", 2)
        headers[k.downcase] = (v || "").strip
      end
      body = ""
      if headers["content-length"]
        clen = headers["content-length"].to_i
        body = sock.read(clen) || ""
      end

      key = [method.to_s.upcase, path.split("?").first]
      handler = @responders[key]

      if handler.nil?
        respond(sock, 404, { "Content-Type" => "text/plain" }, "not found")
        return
      end

      resp = handler.call({ method: method, path: path, headers: headers, body: body })

      if resp == :sse
        # emit 3 SSE data lines and close
        sock.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
        3.times do |i|
          sock.write("data: event-#{i}\n\n")
          sock.flush
          sleep 0.05
        end
        sock.close
      elsif resp == :chunk
        # chunked transfer, 3 chunks
        sock.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n")
        ["{\"a\":1}", "{\"b\":2}", "{\"c\":3}"].each do |ch|
          sock.write("%x\r\n%s\r\n" % [ch.bytesize, ch])
          sock.flush
          sleep 0.05
        end
        sock.write("0\r\n\r\n")
        sock.close
      else
        status, headers_out, body_out = resp
        respond(sock, status, headers_out, body_out)
      end
    rescue => e
      begin
        respond(sock, 500, { "Content-Type" => "text/plain" }, e.message)
      rescue
      ensure
        sock.close rescue nil
      end
    end

    def respond(sock, status, headers, body)
      body = body.to_s
      hdr = "HTTP/1.1 #{status} OK\r\n"
      headers = { "Content-Type" => "application/json", "Content-Length" => body.bytesize.to_s }.merge(headers || {})
      headers.each { |k, v| hdr << "#{k}: #{v}\r\n" }
      hdr << "\r\n"
      sock.write(hdr)
      sock.write(body)
      sock.close
    end

    def shutdown
      @server.close rescue nil
      @thr.kill rescue nil
    end
  end

  # Tiny TCP/UDP test servers
  class TcpEcho
    attr_reader :port

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thr = Thread.new do
        begin
          loop do
            s = @server.accept
            worker = Thread.new(s) do |sock|
              begin
                while (line = sock.gets)
                  sock.write(line)
                end
              rescue IOError, SystemCallError
              ensure
                sock.close rescue nil
              end
            end
            worker.report_on_exception = false
          end
        rescue IOError, SystemCallError
          # server socket closed during shutdown
        end
      end
      @thr.report_on_exception = false
    end

    def shutdown
      @server.close rescue nil
      @thr.kill rescue nil
    end
  end

  class UdpEcho
    attr_reader :port
    
    def initialize
      @sock = UDPSocket.new
      @sock.bind("127.0.0.1", 0)
      @port = @sock.addr[1]
      @thr = Thread.new do
        begin
          loop do
            data, addr = @sock.recvfrom(2048)
            @sock.send(data, 0, addr[3], addr[1]) rescue nil
          end
        rescue IOError, SystemCallError
          # socket closed during shutdown
        end
      end
      @thr.report_on_exception = false
    end

    def shutdown
      @sock.close rescue nil
      @thr.kill rescue nil
    end
  end
end
