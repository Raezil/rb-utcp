# UTCP Example Servers and Clients

Small standalone servers demonstrating transports supported by the `rb-utcp` library. Each
example lives in its own directory containing a server, client and a `providers.json` file used by
the client.

Start a server and then run the corresponding client in another terminal:

```
ruby examples/http/server.rb          # prints http://127.0.0.1:PORT
ruby examples/http/client.rb http://127.0.0.1:PORT

ruby examples/websocket/server.rb     # prints ws://127.0.0.1:PORT/
ruby examples/websocket/client.rb ws://127.0.0.1:PORT/

ruby examples/graphql/server.rb       # requires graphql gem; prints http://127.0.0.1:PORT/graphql
ruby examples/graphql/client.rb http://127.0.0.1:PORT/graphql

ruby examples/tcp/server.rb           # prints TCP port
ruby examples/tcp/client.rb PORT

ruby examples/udp/server.rb           # prints UDP port
ruby examples/udp/client.rb PORT

ruby examples/mcp/server.rb           # prints http://127.0.0.1:PORT
ruby examples/mcp/client.rb http://127.0.0.1:PORT
```

The GraphQL example depends on the `graphql` gem. Install it with:

```
gem install graphql
```

These servers and clients are intentionally minimal and do not perform any authentication. They are
meant for local experimentation with the corresponding UTCP providers.

