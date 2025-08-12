# frozen_string_literal: true
module Utcp
  module Providers
    class BaseProvider
      attr_reader :name, :type, :auth

      def initialize(name:, provider_type:, auth: nil)
        @name = name
        @type = provider_type
        @auth = auth
      end

      # Returns [Array<Tool>]
      def discover_tools!
        raise NotImplementedError
      end

      # Execute a tool, possibly streaming chunks via &block
      def call_tool(tool, arguments = {}, &block)
        raise NotImplementedError
      end
    end
  end
end
