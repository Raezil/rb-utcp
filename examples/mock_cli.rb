#!/usr/bin/env ruby
require 'json'

manual = {
  tools: [
    {
      name: 'echo',
      description: 'Echo the provided message',
      input_schema: { type: 'object', properties: { message: { type: 'string' } }, required: ['message'] },
      output_schema: { type: 'string' }
    }
  ]
}

if ARGV.empty?
  puts JSON.pretty_generate(manual)
  exit 0
end

if ARGV.include?('--help')
  warn "Usage: #{File.basename($0)} [--message TEXT]"
  exit 1
end

index = ARGV.index('--message')
if index
  puts ARGV[index + 1].to_s
else
  warn "Missing --message"
  exit 1
end
