# frozen_string_literal: true
require "uri"
require "json"
require "net/http"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "../auth"
require_relative "../tool"
require_relative "base_provider"

module Utcp
  module Providers
    # Minimal HTTP-based MCP provider.
    # Works in two modes:
    #  - Manual discovery: GET {url}{discovery_path} returns a UTCP manual (tools array).
    #  - Execution: POST {url}{call_path} with {"tool": name, "arguments": {...}}.
    #
    # Streaming:
    #  - If the server replies with 'text/event-stream', we'll parse SSE 'data:' lines and yield them.
    #  - Otherwise, if a block is given, chunks from the HTTP body are yielded as they arrive.
    class McpProvider < BaseProvider
      def initialize(name:, url:, headers: {}, auth: nil, manual: false, discovery_path: "/manual", call_path: "/call")
        super(name: name, provider_type: manual ? "mcp_manual" : "mcp", auth: auth)
        @url = Utils::Subst.apply(url)
        @headers = Utils::Subst.apply(headers || {})
        @manual = manual
        @discovery_path = discovery_path
        @call_path = call_path
      end

      def discover_tools!
        raise ProviderError, "Not a manual provider" unless @manual
        uri = URI(join_path(@url, @discovery_path))
        req = Net::HTTP::Get.new(uri)
        headers = default_headers
        apply_auth!(uri, headers)
        headers.each { |k, v| req[k] = v }

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          res = http.request(req)
          raise ProviderError, "MCP discovery failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
          manual = JSON.parse(res.body)
          to_tools(manual)
        ensure
          http.finish if http.active?
        end
      end

      # Expects tool.provider to include MCP endpoint info:
      # { "provider_type": "mcp", "url": "http://host:port/mcp",
      #   "call_path": "/call", "headers": { ... } }
      def call_tool(tool, arguments = {}, &block)
        p = tool.provider || {}
        base = Utils::Subst.apply(p["url"] || @url)
        call_path = p["call_path"] || @call_path
        uri = URI(join_path(base, call_path))

        body = { "tool" => tool.name, "arguments" => Utils::Subst.apply(arguments || {}) }
        req = Net::HTTP::Post.new(uri)
        headers = default_headers.merge({ "Content-Type" => "application/json" }).merge(Utils::Subst.apply(p["headers"] || {}))
        apply_auth!(uri, headers)
        headers.each { |k, v| req[k] = v }
        req.body = JSON.dump(body)

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          if block_given?
            http.request(req) do |res|
              ctype = (res["Content-Type"] || "").downcase
              if ctype.include?("text/event-stream")
                buffer = +""
                res.read_body do |chunk|
                  buffer << chunk
                  while (line = buffer.slice!(/.*\n/))
                    line = line.strip
                    next if line.empty? || line.start_with?(":")
                    if line.start_with?("data:")
                      data = line.sub(/^data:\s?/, "")
                      yield data
                    end
                  end
                end
              else
                res.read_body do |chunk|
                  yield chunk
                end
              end
            end
            nil
          else
            res = http.request(req)
            begin
              JSON.parse(res.body)
            rescue
              res.body
            end
          end
        ensure
          http.finish if http.active?
        end
      end

      private

      def default_headers
        { "User-Agent" => "ruby-utcp/#{Utcp::VERSION}" }.merge(@headers || {})
      end

      def apply_auth!(uri, headers)
        if @auth
          @auth.apply_query(uri) if @auth.respond_to?(:apply_query)
          @auth.apply_headers(headers)
        end
      end

      def to_tools(manual)
        (manual["tools"] || []).map do |t|
          Utcp::Tool.new(
            name: t["name"],
            description: t["description"],
            inputs: t["inputs"],
            outputs: t["outputs"],
            tags: t["tags"] || [],
            provider: t["tool_provider"] || {}
          )
        end
      end

      def join_path(base, path)
        return base.to_s if path.to_s.empty?
        if base.end_with?("/")
          base + path.sub(%r{^/}, "")
        else
          base + path
        end
      end
    end
  end
end
