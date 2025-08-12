# frozen_string_literal: true
require "base64"
require "json"
require "uri"
require "net/http"
require_relative "errors"
require_relative "utils/subst"

module Utcp
  module Auth
    class Base
      def apply_headers(h) = h
      def apply_query(uri) = uri
    end

    class ApiKey < Base
      def initialize(api_key:, var_name: "Authorization", location: "header")
        @api_key = Utils::Subst.apply(api_key)
        @var_name = var_name
        @location = location
      end

      def apply_headers(h)
        return h unless @location == "header"
        h[@var_name] = @api_key
        h
      end

      def apply_query(uri)
        return uri unless @location == "query"
        q = URI.decode_www_form(uri.query || "") << [@var_name, @api_key]
        uri.query = URI.encode_www_form(q)
        uri
      end

      def apply_cookies(existing = "")
        return existing unless @location == "cookie"
        cookie = "#{@var_name}=#{@api_key}"
        existing.to_s.empty? ? cookie : "#{existing}; #{cookie}"
      end
    end

    class Basic < Base
      def initialize(username:, password:)
        @cred = Base64.strict_encode64("#{Utils::Subst.apply(username)}:#{Utils::Subst.apply(password)}")
      end

      def apply_headers(h)
        h["Authorization"] = "Basic #{@cred}"
        h
      end
    end

    class OAuth2 < Base
      def initialize(token_url:, client_id:, client_secret:, scope: nil)
        @token_url = Utils::Subst.apply(token_url)
        @client_id = Utils::Subst.apply(client_id)
        @client_secret = Utils::Subst.apply(client_secret)
        @scope = scope && Utils::Subst.apply(scope)
        @cached = nil
        @expires_at = Time.at(0)
      end

      def apply_headers(h)
        token = fetch_token
        h["Authorization"] = "Bearer #{token}"
        h
      end

      private

      def fetch_token
        return @cached if Time.now < @expires_at && @cached
        uri = URI(@token_url)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/x-www-form-urlencoded"
        form = { "grant_type" => "client_credentials", "client_id" => @client_id, "client_secret" => @client_secret }
        form["scope"] = @scope if @scope && !@scope.empty?
        req.body = URI.encode_www_form(form)

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        begin
          res = http.request(req)
          raise AuthError, "OAuth2 token request failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
          data = JSON.parse(res.body)
          @cached = data["access_token"] || data["token"] || data["id_token"]
          ttl = (data["expires_in"] || 3600).to_i
          @expires_at = Time.now + ttl - 30
          @cached or raise AuthError, "OAuth2 response missing token"
        ensure
          http.finish if http.active?
        end
      end
    end

    def self.from_hash(h)
      return nil unless h.is_a?(Hash)
      type = (h["auth_type"] || h["type"] || "").downcase
      case type
      when "api_key", "apikey"
        ApiKey.new(api_key: h["api_key"] || h["key"] || "", var_name: h["var_name"] || "Authorization", location: (h["location"] || "header"))
      when "basic"
        Basic.new(username: h["username"] || "", password: h["password"] || "")
      when "oauth2"
        OAuth2.new(token_url: h["token_url"] || h["tokenUrl"] || "", client_id: h["client_id"] || "", client_secret: h["client_secret"] || "", scope: h["scope"])
      else
        nil
      end
    end
  end
end
