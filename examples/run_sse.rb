require_relative '../utcp_client'
require_relative '../repository'
require_relative '../tag_search'
require_relative '../utcp_config'

Async do
  cfg = UtcpClientConfig.new(providers_file_path: File.expand_path('providers_sse.json', __dir__))
  client = UtcpClient.create(config: cfg).wait
  enum = client.call_tool('ssedemo.stream', {}).wait
  enum.each { |e| puts "Event: #{e}" }
end
