require_relative '../utcp_client'
require_relative '../repository'
require_relative '../tag_search'
require_relative '../utcp_config'

Async do
  cfg = UtcpClientConfig.new(
    providers_file_path: File.expand_path('providers_mcp.json', __dir__)
  )
  client = UtcpClient.create(config: cfg).wait

  tools = client.search_tools("", 10).wait

  # Print summary of each tool
  tools.each do |tool|
    # Depending on the returned structure, adjust accessors (hash vs object)
    name = tool.respond_to?(:name) ? tool.name : tool['name']
    desc = tool.respond_to?(:description) ? tool.description : tool['description']
    puts "Found tool: #{name} - #{desc}"
  end

  # Example: concurrently call each tool if you have safe default input
  # Here we only call 'mcpdemo.echo' as an example
  echo_tool = tools.find do |tool|
    name = tool.respond_to?(:name) ? tool.name : tool['name']
    name == 'mcpdemo.echo'
  end

  if echo_tool
    # Fire off the call inside its own task so others wouldn’t block (if you extended to more)
    Async do
      begin
        result = client.call_tool('mcpdemo.echo', { message: 'hello from loop' }).wait
        puts "Result from mcpdemo.echo: #{result}"
      rescue => e
        warn "Error calling mcpdemo.echo: #{e.class}: #{e.message}"
      end
    end.wait
  else
    puts "Echo tool not found among returned tools."
  end
end
