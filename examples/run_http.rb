require_relative '../utcp_client'
require_relative '../repository'
require_relative '../tag_search'
require_relative '../utcp_config'

Async do
  cfg = UtcpClientConfig.new(providers_file_path: File.expand_path('providers_http.json', __dir__))
  client = UtcpClient.create(config: cfg).wait
  result = client.call_tool('httpdemo.echo', { message: 'hello http' }).wait
  puts "Result: #{result}"
end
