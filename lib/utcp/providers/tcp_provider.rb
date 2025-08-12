# frozen_string_literal: true
require "socket"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # Raw TCP provider
    # tool.provider: { "provider_type":"tcp", "host":"127.0.0.1","port":5001,
    #                  "message_template":"hello ${name}\n",
    #                  "read_until":"\n", "timeout_ms": 2000 }
    class TcpProvider < BaseProvider
      def initialize(name:)
        super(name: name, provider_type: "tcp", auth: nil)
      end

      def discover_tools!
        raise ProviderError, "TCP is an execution provider only"
      end

      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        host = p["host"] || "127.0.0.1"
        port = (p["port"] || 5001).to_i
        timeout = (p["timeout_ms"] || 2000).to_i / 1000.0
        msg = compose_message(p, arguments)

        socket = TCPSocket.new(host, port)
        begin
          socket.write(msg) if msg
          if block_given?
            stream_read(socket, timeout: timeout) { |chunk| yield chunk }
            nil
          else
            read_until = p["read_until"]
            if read_until
              read_until_delim(socket, read_until, timeout: timeout)
            else
              socket.read
            end
          end
        ensure
          socket.close rescue nil
        end
      end

      private

      def compose_message(p, arguments)
        args = Utils::Subst.apply(arguments || {})
        if p["message_template"]
          tmpl = p["message_template"]
          tmpl.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) { |m| args[$1] || ENV[$1] || m }
        else
          nil
        end
      end

      def stream_read(sock, timeout: 2)
        loop do
          ready = IO.select([sock], nil, nil, timeout)
          break unless ready
          chunk = sock.read_nonblock(4096, exception: false)
          break unless chunk
          yield chunk
        end
      end

      def read_until_delim(sock, delim, timeout: 2)
        buf = +"".b
        loop do
          ready = IO.select([sock], nil, nil, timeout)
          break unless ready
          c = sock.readpartial(1) rescue break
          buf << c
          break if buf.end_with?(delim)
        end
        buf
      end
    end
  end
end
