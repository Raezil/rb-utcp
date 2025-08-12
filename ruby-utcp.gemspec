# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name        = "rb-utcp"
  s.version     = "0.1.0"
  s.summary     = "Universal Tool Calling Protocol (Ruby, alpha)"
  s.description = "Minimal Ruby implementation of UTCP with HTTP/SSE/HTTP-stream transports."
  s.authors     = ["UTCP contributors"]
  s.email       = ["dev@utcp.io"]
  s.files       = Dir["lib/**/*.rb"] + Dir["README.md"] + Dir["LICENSE"]
  s.executables << "utcp"
  s.required_ruby_version = ">= 3.0.0"
  s.license     = "MPL-2.0"
end
