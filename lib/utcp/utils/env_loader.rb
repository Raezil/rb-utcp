# frozen_string_literal: true
module Utcp
  module Utils
    class EnvLoader
      # Loads simple KEY=VALUE pairs into ENV (no interpolation here)
      def self.load_file(path = ".env")
        return {} unless File.file?(path)
        vars = {}
        File.readlines(path, chomp: true).each do |line|
          next if line.strip.empty? || line.strip.start_with?("#")
          key, value = line.split("=", 2)
          next unless key
          value ||= ""
          value = value.strip.strip('"').strip("'")
          ENV[key.strip] = value
          vars[key.strip] = value
        end
        vars
      end
    end
  end
end
