# rb-utcp

This project contains a minimal Ruby implementation of an experimental UTCP client.
It provides several transport implementations and a basic client that can load
provider definitions from JSON files.

## Running the example

```
cd examples
ruby run.rb
```

The example registers a text provider defined in `providers.json` and calls the
`echo` tool from `echo_tool.json`.

## Transport Examples

Additional example scripts are available under `examples/` for other transports. These include small mock servers and a CLI to demonstrate usage:

- `mock_http_server.rb` with `run_http.rb`
- `mock_sse_server.rb` with `run_sse.rb`
- `mock_http_stream_server.rb` with `run_stream.rb`
- `mock_cli.rb` with `run_cli.rb`
- `mock_graphql_server.rb` with `run_graphql.rb`
- `run_mcp.rb` (requires an MCP server)

Start the corresponding mock server (or CLI) and run the matching `run_*.rb` script from the `examples` directory.
