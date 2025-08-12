# frozen_string_literal: true
require_relative "test_helper"
require "utcp/utils/subst"
require "utcp/utils/env_loader"

class UtilsTest < Minitest::Test
  def test_subst_string_and_hash
    ENV["USER_NAME"] = "kamil"
    s = Utcp::Utils::Subst.apply("hello ${USER_NAME}")
    assert_equal "hello kamil", s

    h = Utcp::Utils::Subst.apply({ "greet" => "hi ${USER_NAME}", "x" => 1 })
    assert_equal "hi kamil", h["greet"]
    assert_equal 1, h["x"]
  end

  def test_env_loader
    Dir.mktmpdir do |d|
      path = File.join(d, ".env")
      File.write(path, "A=1\nB=two\n# comment\n")
      vars = Utcp::Utils::EnvLoader.load_file(path)
      assert_equal "1", ENV["A"]
      assert_equal "two", ENV["B"]
      assert_equal({ "A"=>"1", "B"=>"two" }, vars)
    end
  end
end
