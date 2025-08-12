# frozen_string_literal: true
require "uri"
require "net/http"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # Simple HTTP chunked transfer streaming
    class HttpStreamProvider < BaseProvider
      def initialize(name:, auth: nil)
        super(name: name, provider_type: "http_stream", auth: auth)
      end

      def discover_tools!
        raise ProviderError, "HTTP stream is an execution provider only"
      end

      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        url = Utils::Subst.apply(p["url"])
        method = (p["http_method"] || "GET").upcase
        uri = URI(url)

        args = Utils::Subst.apply(arguments || {})
        if %w[GET DELETE].include?(method)
          q = URI.decode_www_form(uri.query || "") + args.to_a
          uri.query = URI.encode_www_form(q)
        end

        req = Net::HTTP.const_get(method.capitalize).new(uri)
        headers = { "Accept" => "application/json" }
        @auth&.apply_query(uri) if @auth&.respond_to?(:apply_query)
        @auth&.apply_headers(headers)
        headers.each { |k, v| req[k] = v }

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          http.request(req) do |res|
            res.read_body do |chunk|
              yield chunk if block_given?
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
