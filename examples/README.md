# UTCP Example Servers and Clients

Small standalone servers demonstrating transports supported by the `rb-utcp` library.
Each script binds to `127.0.0.1` on a random available port and prints its URL on startup.

For each server there is a matching client script showing how to call it using `Utcp::Client`.
Start a server and then run the corresponding client in another terminal:

```
ruby examples/http_server.rb          # prints http://127.0.0.1:PORT
ruby examples/http_client.rb http://127.0.0.1:PORT

ruby examples/websocket_server.rb     # prints ws://127.0.0.1:PORT/
ruby examples/websocket_client.rb ws://127.0.0.1:PORT/

ruby examples/graphql_server.rb       # requires graphql gem; prints http://127.0.0.1:PORT/graphql
ruby examples/graphql_client.rb http://127.0.0.1:PORT/graphql

ruby examples/tcp_echo_server.rb      # prints TCP port
ruby examples/tcp_client.rb PORT

ruby examples/udp_echo_server.rb      # prints UDP port
ruby examples/udp_client.rb PORT

ruby examples/mcp_server.rb           # prints http://127.0.0.1:PORT
ruby examples/mcp_client.rb http://127.0.0.1:PORT
```

The GraphQL example depends on the `graphql` gem. Install it with:

```
gem install graphql
```

These servers and clients are intentionally minimal and do not perform any authentication.
They are meant for local experimentation with the corresponding UTCP providers.
