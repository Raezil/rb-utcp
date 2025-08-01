require_relative '../utcp_client'
require_relative '../repository'
require_relative '../tag_search'
require_relative '../utcp_config'
require_relative '../text_transport'
require_relative '../models'

Async do
  config = UtcpClientConfig.new(providers_file_path: File.expand_path('providers.json', __dir__))
  client = UtcpClient.create(config: config)
  result = client.call_tool('example.echo', { message: 'hello world' })
  puts "Result: #{result}"
end
