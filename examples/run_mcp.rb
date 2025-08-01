require_relative '../utcp_client'
require_relative '../repository'
require_relative '../tag_search'
require_relative '../utcp_config'

Async do
  cfg = UtcpClientConfig.new(providers_file_path: File.expand_path('providers_mcp.json', __dir__))
  client = UtcpClient.create(config: cfg).wait
  # This example assumes an MCP server is running as configured
  result = client.call_tool('mcpdemo.echo', { message: 'hello mcp' }).wait
  puts "Result: #{result}"
end
