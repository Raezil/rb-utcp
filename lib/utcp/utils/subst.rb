# frozen_string_literal: true
require "json"

module Utcp
  module Utils
    module Subst
      VAR_RE = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}/.freeze

      module_function

      def apply(obj, vars = ENV)
        case obj
        when String
          obj.gsub(VAR_RE) { |m| vars[$1] || m }
        when Array
          obj.map { |x| apply(x, vars) }
        when Hash
          obj.transform_values { |v| apply(v, vars) }
        else
          obj
        end
      end
    end
  end
end
