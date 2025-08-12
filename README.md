# ruby-utcp (alpha)

A small, dependency-light Ruby implementation of the **Universal Tool Calling Protocol (UTCP)**.
It mirrors the core models — **Manual**, **Tool**, **Providers**, and **Auth** — and lets you
discover tools and call them over HTTP, SSE, and HTTP chunked streams.

> Status: early alpha, but usable for simple demos. Standard library only.

## Features
- Load one or more "manual providers" from `providers.json` (HTTP or local file).
- Store discovered tools in an in-memory repository.
- Call tools via HTTP (`GET/POST/PUT/PATCH/DELETE`), SSE, or HTTP chunked streaming.
- API Key, Basic, and OAuth2 Client Credentials auth (token cached in memory).
- Simple variable substitution for `${VAR}` using values from environment and `.env` files.
- Tiny search helper scoring tags + description to find relevant tools.

## Install
This is a vanilla Ruby project. No external gems are required.
```bash
ruby -v   # Ruby 3.x recommended
```

## Quickstart
```bash
# 1) Unzip, cd in
cd ruby-utcp

# 2) (Optional) create a .env file with secrets
echo 'OPEN_WEATHER_API_KEY=replace-me' > .env

# 3) Run the example (uses httpbin.org)
ruby examples/basic_call.rb
```

## Layout
```
lib/utcp.rb
lib/utcp/version.rb
lib/utcp/client.rb
lib/utcp/tool.rb
lib/utcp/errors.rb
lib/utcp/utils/env_loader.rb
lib/utcp/utils/subst.rb
lib/utcp/auth.rb
lib/utcp/tool_repository.rb
lib/utcp/search.rb
lib/utcp/providers/base_provider.rb
lib/utcp/providers/http_provider.rb
lib/utcp/providers/sse_provider.rb
lib/utcp/providers/http_stream_provider.rb
bin/utcp
examples/providers.json
examples/tools_weather.json
examples/basic_call.rb
```

## Example manual (local file)
See `examples/tools_weather.json` for a minimal UTCP manual that exposes two tools:
- `echo` (POST JSON to httpbin.org)
- `stream_http` (stream 20 JSON lines from httpbin.org)

## CLI
```bash
# List all discovered tools
ruby bin/utcp list examples/providers.json

# Call a tool (args as JSON)
ruby bin/utcp call examples/providers.json echo --args '{"message":"hello"}'
```

## License
MPL-2.0


## New transports (alpha)
- **WebSocket**: minimal RFC6455 text-only client; great for echo/testing.
- **GraphQL**: POST query + variables to any GraphQL endpoint.
- **TCP/UDP**: raw sockets with simple `${var}` templating; includes local echo servers under `examples/dev/`.
- **CLI**: call local commands (use carefully!).

### Try them
Start local echo servers (optional, for TCP/UDP):
```bash
ruby examples/dev/echo_tcp_server.rb 5001
ruby examples/dev/echo_udp_server.rb 5002
```

Use the extra providers file:
```bash
ruby bin/utcp list examples/providers_extra.json
ruby bin/utcp call examples/providers_extra.json ws_demo.ws_echo --args '{"text":"hello ws"}' --stream
ruby bin/utcp call examples/providers_extra.json cli_demo.shell_echo --args '{"msg":"hi from shell"}'
ruby bin/utcp call examples/providers_extra.json sock_demo.tcp_echo --args '{"name":"kamil"}'
ruby bin/utcp call examples/providers_extra.json gql_demo.country_by_code --args '{"code":"DE"}'
```


## MCP provider
This adds a minimal HTTP-based MCP bridge.

### Discovery
Manual discovery expects the server to return a UTCP manual at `{url}/manual` (configurable via `discovery_path`). Point a manual provider to `"provider_type": "mcp"` in `providers.json` to fetch tools.

### Calls
Tools with `"provider_type": "mcp"` will POST to `{url}/call` with:
```json
{ "tool": "<name>", "arguments": { "...": "..." } }
```
If the response is `text/event-stream` we parse SSE and yield each `data:` line; otherwise we stream raw chunks when `--stream` is used.

### Example
```bash
# assuming an MCP test server on http://localhost:8220/mcp
ruby bin/utcp list examples/providers_mcp.json
ruby bin/utcp call examples/providers_mcp.json mcp_demo.hello --args '{"name":"Kamil"}'
```


## Tests
This project uses **Minitest** (stdlib only).

Run all tests:
```bash
ruby bin/test
```
or
```bash
ruby -Ilib -Itest -rminitest/autorun test/*_test.rb
```
