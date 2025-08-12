# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "json"
require "utcp"

client = Utcp::Client.create({
  "providers_file_path" => File.expand_path("providers.json", __dir__),
  "load_variables_from" => [File.expand_path("../.env", __dir__)]
})

puts "Tools found:"
client.search_tools("echo stream").each do |score, tool|
  # find provider for display
  provider = client.repo.providers.find { |p| client.repo.find("\#{p}.\#{tool.name}") rescue nil }
  puts "  - \#{provider}.\#{tool.name} (score=\#{score})"
end

puts "\nCalling echo..."
res = client.call_tool("local_examples.echo", { "message" => "Hello UTCP from Ruby!" })
puts JSON.pretty_generate(res)

puts "\nStreaming (first 5 chunks) from httpbin..."
count = 0
client.call_tool("local_examples.stream_http", {}, stream: true) do |chunk|
  puts chunk
  count += 1
  break if count >= 5
end

puts "\nDone."
