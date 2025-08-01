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
