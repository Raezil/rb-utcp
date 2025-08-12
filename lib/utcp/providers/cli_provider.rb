# frozen_string_literal: true
require "open3"
require_relative "../utils/subst"
require_relative "../errors"
require_relative "base_provider"

module Utcp
  module Providers
    # CLI provider for executing local commands (use with caution)
    # tool.provider: { "provider_type":"cli", "command":["echo","hello ${name}"] }
    class CliProvider < BaseProvider
      def initialize(name:)
        super(name: name, provider_type: "cli", auth: nil)
      end

      def discover_tools!
        raise ProviderError, "CLI is an execution provider only"
      end

      def call_tool(tool, arguments = {}, &block)
        p = tool.provider
        cmd = p["command"]
        raise ConfigError, "cli provider requires 'command' array" unless cmd.is_a?(Array) && !cmd.empty?
        args = Utils::Subst.apply(arguments || {})

        expanded = cmd.map do |part|
          part.to_s.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) { |m| args[$1] || ENV[$1] || m }
        end

        stdout, stderr, status = Open3.capture3(*expanded)
        {
          "ok" => status.success?,
          "exit_code" => status.exitstatus,
          "stdout" => stdout,
          "stderr" => stderr
        }
      end
    end
  end
end
