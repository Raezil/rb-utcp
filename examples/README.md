# UTCP Example Servers

Small standalone servers demonstrating transports supported by the `rb-utcp` library.
Each script binds to `127.0.0.1` on a random available port and prints its URL on startup.

Run examples with Ruby:

```
ruby examples/http_server.rb
ruby examples/websocket_server.rb
ruby examples/graphql_server.rb
ruby examples/tcp_echo_server.rb
ruby examples/udp_echo_server.rb
ruby examples/mcp_server.rb
```

These servers are intentionally minimal and do not perform any authentication.
They are meant for local experimentation with the corresponding UTCP providers.
