# frozen_string_literal: true
require "json"

module Utcp
  Tool = Struct.new(:name, :description, :inputs, :outputs, :tags, :provider, keyword_init: true) do
    def full_name(provider_name)
      "#{provider_name}.#{name}"
    end
  end
end
