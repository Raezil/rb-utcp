# frozen_string_literal: true
module Utcp
  class Error < StandardError; end
  class ConfigError < Error; end
  class NotFoundError < Error; end
  class AuthError < Error; end
  class ProviderError < Error; end
end
