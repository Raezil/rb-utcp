# frozen_string_literal: true
require "uri"
require "json"
require "net/http"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "../auth"
require_relative "base_provider"

module Utcp
  module Providers
    # Simple GraphQL over HTTP
    # tool.provider: { "provider_type":"graphql", "url":"https://...",
    #                  "query":"query ($code:String!) { country(code:$code){name}}",
    #                  "operationName": "...optional..." }
    class GraphQLProvider < BaseProvider
      def initialize(name:, auth: nil, headers: {})
        super(name: name, provider_type: "graphql", auth: auth)
        @headers = headers || {}
      end

      def discover_tools!
        raise ProviderError, "GraphQL is an execution provider only"
      end

      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        url = Utils::Subst.apply(p["url"])
        uri = URI(url)
        body = {
          "query" => Utils::Subst.apply(p["query"]),
          "variables" => Utils::Subst.apply(arguments || {})
        }
        body["operationName"] = p["operationName"] if p["operationName"]

        req = Net::HTTP::Post.new(uri)
        headers = { "Content-Type" => "application/json" }.merge(@headers)
        @auth&.apply_headers(headers)
        headers.each { |k, v| req[k] = v }
        req.body = JSON.dump(body)

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          res = http.request(req)
          JSON.parse(res.body) rescue res.body
        ensure
          http.finish if http.active?
        end
      end
    end
  end
end
