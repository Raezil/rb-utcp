# frozen_string_literal: true
require_relative "test_helper"
require "utcp/auth"

class AuthTest < Minitest::Test
  def test_api_key_header
    a = Utcp::Auth::ApiKey.new(api_key: "KEY", var_name: "X-API", location: "header")
    h = a.apply_headers({})
    assert_equal "KEY", h["X-API"]
  end

  def test_api_key_query
    a = Utcp::Auth::ApiKey.new(api_key: "KEY", var_name: "token", location: "query")
    uri = URI("https://example.com/echo")
    a.apply_query(uri)
    assert_equal "token=KEY", uri.query
  end

  def test_basic
    a = Utcp::Auth::Basic.new(username: "u", password: "p")
    h = a.apply_headers({})
    assert_match /^Basic /, h["Authorization"]
  end
end
