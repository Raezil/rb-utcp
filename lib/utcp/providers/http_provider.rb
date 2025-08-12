# frozen_string_literal: true
require "uri"
require "json"
require "net/http"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "../tool"
require_relative "../auth"
require_relative "base_provider"

module Utcp
  module Providers
    class HttpProvider < BaseProvider
      def initialize(name:, url:, http_method: "GET", content_type: "application/json", headers: {}, manual: false, auth: nil, body_field: nil)
        super(name: name, provider_type: manual ? "http_manual" : "http", auth: auth)
        @url = Utils::Subst.apply(url)
        @http_method = http_method.upcase
        @content_type = content_type
        @headers = Utils::Subst.apply(headers || {})
        @manual = manual
        @body_field = body_field
      end

      def discover_tools!
        raise ProviderError, "Not a manual provider" unless @manual
        uri = URI(@url)
        req = Net::HTTP.const_get(@http_method.capitalize).new(uri)
        headers = default_headers
        apply_auth!(uri, headers)
        headers.each { |k, v| req[k] = v }

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          res = http.request(req)
          raise ProviderError, "Manual fetch failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
          manual = JSON.parse(res.body)
          to_tools(manual)
        ensure
          http.finish if http.active?
        end
      end

      def call_tool(tool, arguments = {}, &block)
        # tool.provider is a hash containing execution provider details
        p = tool.provider
        url = Utils::Subst.apply(p["url"] || @url)
        method = (p["http_method"] || @http_method || "GET").upcase
        content_type = p["content_type"] || @content_type || "application/json"
        headers = Utils::Subst.apply(p["headers"] || {}).merge(default_headers)
        body_field = p["body_field"] || @body_field

        uri = URI(url)
        args = Utils::Subst.apply(arguments || {})
        if %w[GET DELETE].include?(method)
          q = URI.decode_www_form(uri.query || "") + args.to_a
          uri.query = URI.encode_www_form(q)
          req = Net::HTTP.const_get(method.capitalize).new(uri)
        else
          req = Net::HTTP.const_get(method.capitalize).new(uri)
          if body_field
            payload = { body_field => args }
          else
            payload = args
          end
          if content_type.include?("json")
            req.body = JSON.dump(payload)
            req["Content-Type"] = "application/json"
          else
            req.body = URI.encode_www_form(payload)
            req["Content-Type"] = "application/x-www-form-urlencoded"
          end
        end

        # auth
        headers = headers.transform_keys(&:to_s)
        apply_auth!(uri, headers)
        req["Cookie"] = [req["Cookie"], @auth&.apply_cookies].compact.join("; ") if @auth.respond_to?(:apply_cookies)
        headers.each { |k, v| req[k] = v }

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          res = http.request(req)
          # try to parse as JSON; fall back to raw string
          begin
            JSON.parse(res.body)
          rescue
            res.body
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
        tools = (manual["tools"] || []).map do |t|
          Utcp::Tool.new(
            name: t["name"],
            description: t["description"],
            inputs: t["inputs"],
            outputs: t["outputs"],
            tags: t["tags"] || [],
            provider: t["tool_provider"] || {}
          )
        end
        tools
      end
    end
  end
end
