require_relative 'test_helper'
require 'utcp_config'

class UtcpConfigTest < Minitest::Test
  def test_model_validate
    cfg = UtcpClientConfig.model_validate({ 'providers_file_path' => 'p.json' })
    assert_equal 'p.json', cfg.providers_file_path
  end
end
