# frozen_string_literal: true
require "socket"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # UDP provider (best-effort, may drop packets)
    # tool.provider: { "provider_type":"udp", "host":"127.0.0.1","port":5002,
    #                  "message_template":"ping ${name}", "timeout_ms": 1000, "max_bytes": 2048 }
    class UdpProvider < BaseProvider
      def initialize(name:)
        super(name: name, provider_type: "udp", auth: nil)
      end

      def discover_tools!
        raise ProviderError, "UDP is an execution provider only"
      end

      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        host = p["host"] || "127.0.0.1"
        port = (p["port"] || 5002).to_i
        timeout = (p["timeout_ms"] || 1000).to_i / 1000.0
        max_bytes = (p["max_bytes"] || 2048).to_i
        msg = compose_message(p, arguments)

        udp = UDPSocket.new
        udp.connect(host, port)
        begin
          udp.send(msg.to_s, 0)
          if block_given?
            if IO.select([udp], nil, nil, timeout)
              data, _ = udp.recvfrom(max_bytes)
              yield data
            end
            nil
          else
            if IO.select([udp], nil, nil, timeout)
              data, _ = udp.recvfrom(max_bytes)
              data
            else
              nil
            end
          end
        ensure
          udp.close rescue nil
        end
      end

      private

      def compose_message(p, arguments)
        args = Utils::Subst.apply(arguments || {})
        if p["message_template"]
          tmpl = p["message_template"]
          tmpl.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) { |m| args[$1] || ENV[$1] || m }
        else
          ""
        end
      end
    end
  end
end
