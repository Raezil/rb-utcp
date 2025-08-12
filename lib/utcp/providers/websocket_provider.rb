# frozen_string_literal: true
require "socket"
require "openssl"
require "digest/sha1"
require "base64"
require "uri"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # Minimal RFC 6455 WebSocket client (text frames only)
    # Supports ws:// and wss:// (TLS). Client frames are masked; server frames are unmasked.
    class WebSocketProvider < BaseProvider
      GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11".freeze

      def initialize(name:, auth: nil)
        super(name: name, provider_type: "websocket", auth: auth)
      end

      def discover_tools!
        raise ProviderError, "WebSocket is an execution provider only"
      end

      # tool.provider expects:
      # { "provider_type":"websocket", "url":"ws(s)://host/path", "message_template": "...optional..." ,
      #   "close_after_ms": 3000, "max_frames": 1 }
      # If a block is given, yields each received text frame (streaming).
      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        uri = URI(Utils::Subst.apply(p["url"]))
        raise ConfigError, "WebSocket requires ws:// or wss:// URL" unless %w[ws wss].include?(uri.scheme)

        sock = connect_socket(uri)
        begin
          handshake(sock, uri)
          # Compose a text message to send
          payload = compose_payload(p, arguments)
          if payload
            send_text(sock, payload)
          end

          # Read frames; stop based on configuration
          close_after = (p["close_after_ms"] || 3000).to_i
          max_frames = (p["max_frames"] || 1).to_i
          deadline = Time.now + (close_after / 1000.0)
          frames = []
          while Time.now < deadline && frames.length < max_frames
            frame = recv_frame(sock, deadline: deadline)
            break unless frame
            case frame[:opcode]
            when 0x1 # text
              if block_given?
                yield frame[:payload]
              else
                frames << frame[:payload]
              end
            when 0x8 # close
              break
            when 0x9 # ping
              send_pong(sock, frame[:payload])
            when 0xA # pong
              # ignore
            else
              # ignore other opcodes
            end
          end
          block_given? ? nil : frames
        ensure
          begin
            send_close(sock)
          rescue
          end
          sock.close rescue nil
        end
      end

      private

      def connect_socket(uri)
        host = uri.host
        port = uri.port || (uri.scheme == "wss" ? 443 : 80)
        tcp = TCPSocket.new(host, port)
        if uri.scheme == "wss"
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
          ssl.hostname = host
          ssl.sync_close = true
          ssl.connect
          ssl
        else
          tcp
        end
      end

      def handshake(sock, uri)
        key = Base64.strict_encode64(Random.new.bytes(16))
        path = uri.request_uri
        host = uri.host
        headers = [
          "GET #{path} HTTP/1.1",
          "Host: #{host}",
          "Upgrade: websocket",
          "Connection: Upgrade",
          "Sec-WebSocket-Key: #{key}",
          "Sec-WebSocket-Version: 13",
          "", ""
        ].join("\r\n")
        sock.write(headers)

        status_line = sock.gets("\r\n") || ""
        unless status_line.start_with?("HTTP/1.1 101")
          raise ProviderError, "WebSocket handshake failed: #{status_line.strip}"
        end

        # read headers until blank line
        while (line = sock.gets("\r\n"))
          line = line.strip
          break if line.empty?
        end
        # Validation of Sec-WebSocket-Accept skipped for brevity
      end

      def compose_payload(p, arguments)
        args = Utils::Subst.apply(arguments || {})
        if p["message_template"].is_a?(String)
          tmpl = p["message_template"]
          # simple ${key} substitution
          tmpl.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) { |m| args[$1] || ENV[$1] || m }
        elsif args && !args.empty?
          require "json"
          JSON.dump(args)
        else
          nil
        end
      end

      def send_text(sock, text)
        data = text.b
        header = [0x81].pack("C") # FIN=1, opcode=1
        mask_flag = 0x80
        len = data.bytesize
        if len < 126
          header << (mask_flag | len).chr
        elsif len < 65536
          header << (mask_flag | 126).chr << [len].pack("n")
        else
          header << (mask_flag | 127).chr << [len].pack("Q>")
        end
        mask = Random.new.bytes(4)
        masked = data.bytes.each_with_index.map { |b, i| (b ^ mask.getbyte(i % 4)) }.pack("C*")
        sock.write(header + mask + masked)
      end

      def recv_frame(sock, deadline: Time.now + 3)
        header = read_bytes(sock, 2, deadline) or return nil
        b1, b2 = header.bytes
        fin = (b1 & 0x80) != 0
        opcode = b1 & 0x0f
        mask = (b2 & 0x80) != 0
        length = b2 & 0x7f
        if length == 126
          ext = read_bytes(sock, 2, deadline) or return nil
          length = ext.unpack1("n")
        elsif length == 127
          ext = read_bytes(sock, 8, deadline) or return nil
          length = ext.unpack1("Q>")
        end
        mask_key = mask ? read_bytes(sock, 4, deadline) : nil
        payload = read_bytes(sock, length, deadline) or return nil
        if mask_key
          payload = payload.bytes.each_with_index.map { |b, i| (b ^ mask_key.getbyte(i % 4)) }.pack("C*")
        end
        if opcode == 0x1 # text
          payload = payload.force_encoding("UTF-8")
        end
        { fin: fin, opcode: opcode, payload: payload }
      end

      def send_pong(sock, payload="")
        frame = [0x8A].pack("C") # FIN=1 opcode=0xA pong
        mask_flag = 0x80
        len = payload.bytesize
        if len < 126
          frame << (mask_flag | len).chr
        else
          frame << (mask_flag | 126).chr << [len].pack("n")
        end
        mask = Random.new.bytes(4)
        masked = payload.bytes.each_with_index.map { |b, i| (b ^ mask.getbyte(i % 4)) }.pack("C*")
        sock.write(frame + mask + masked)
      end

      def send_close(sock)
        frame = [0x88, 0x80, 0x00, 0x00, 0x00, 0x00].pack("C*") # masked empty close
        sock.write(frame) rescue nil
      end
      
      def read_bytes(sock, n, deadline)
        buf = +"".b
        while buf.bytesize < n
          timeout = [deadline - Time.now, 0].max
          return nil if timeout <= 0
          ready = IO.select([sock], nil, nil, timeout)
          return nil unless ready

          begin
            chunk = sock.readpartial(n - buf.bytesize)
          rescue EOFError, IOError, SystemCallError
            return nil
          end

          return nil if chunk.nil? || chunk.empty?
          buf << chunk
        end
        buf
      end

    end
  end
end
