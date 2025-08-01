# frozen_string_literal: true

# Assuming these are defined elsewhere in your Ruby codebase similarly:
# - Tool (could be a class or struct)
# - ToolContext with a .get_tools method
# - UTCP::VERSION or similar for versioning
#
# If your version is in a different constant, adjust `VERSION_SOURCE` accordingly.

module UTCP
  VERSION_SOURCE = defined?(UTCP::VERSION) ? UTCP::VERSION : '0.0.0' # fallback if not defined
end

class UtcpManual
  attr_reader :version, :tools

  def initialize(version:, tools:)
    @version = version
    @tools = tools
    validate!
  end

  def self.create(version: UTCP::VERSION_SOURCE)
    new(
      version: version,
      tools: ToolContext.get_tools
    )
  end

  def to_h
    {
      version: version,
      tools: tools
    }
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  private

  def validate!
    raise ArgumentError, "version must be a String" unless version.is_a?(String)
    unless tools.respond_to?(:to_ary) || tools.is_a?(Array)
      raise ArgumentError, "tools must be an Array or array-like"
    end
  end
end
