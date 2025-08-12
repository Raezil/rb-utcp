# frozen_string_literal: true
require "uri"
require "net/http"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # Execution provider for Server-Sent Events (SSE)
    class SseProvider < BaseProvider
      def initialize(name:, auth: nil)
        super(name: name, provider_type: "sse", auth: auth)
      end

      # manual discovery not supported here
      def discover_tools!
        raise ProviderError, "SSE is an execution provider only"
      end

      # Expects tool.provider to have: { "url": "...", "http_method": "GET" }
      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        url = Utils::Subst.apply(p["url"])
        uri = URI(url)
        # add args as query
        args = Utils::Subst.apply(arguments || {})
        q = URI.decode_www_form(uri.query || "") + args.to_a
        uri.query = URI.encode_www_form(q)

        req = Net::HTTP::Get.new(uri)
        headers = { "Accept" => "text/event-stream" }
        @auth&.apply_query(uri) if @auth&.respond_to?(:apply_query)
        @auth&.apply_headers(headers)

        headers.each { |k, v| req[k] = v }

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          buffer = +""
          http.request(req) do |res|
            res.read_body do |chunk|
              buffer << chunk
              while (line = buffer.slice!(/.*\n/))
                line = line.strip
                next if line.empty? || line.start_with?(":")
                if line.start_with?("data:")
                  data = line.sub(/^data:\s?/, "")
                  yield data if block_given?
                end
              end
            end
          end
          nil
        ensure
          http.finish if http.active?
        end
      end
    end
  end
end
