# lib/utcp/utils/env_loader.rb
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
          value = value.strip
          # remove optional surrounding quotes
          value = value.gsub(/\A"(.*)"\z/, '\1')
          value = value.gsub(/\A'(.*)'\z/, '\1')
          key = key.strip
          ENV[key] = value
          vars[key] = value
        end
        vars
      end
    end
  end
end
