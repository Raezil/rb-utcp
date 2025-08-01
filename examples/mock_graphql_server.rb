require 'socket'
require 'json'

manual = {
  tools: [
    {
      name: 'query',
      description: 'Simple echo via GraphQL',
      input_schema: { type: 'object', properties: { query: { type: 'string' }, variables: { type: 'object' } }, required: ['query'] },
      output_schema: { type: 'object' }
    }
  ]
}

server = TCPServer.new(4570)
puts 'GraphQL server listening on http://localhost:4570'

trap('INT') { server.close; exit }

def read_request(socket)
  request_line = socket.gets
  return if request_line.nil?
  method, path, _ = request_line.split
  headers = {}
  while (line = socket.gets) && line != "\r\n"
    key, value = line.split(':', 2)
    headers[key] = value.strip if key && value
  end
  body = ''
  if headers['Content-Length']
    body = socket.read(headers['Content-Length'].to_i)
  end
  [method, path, headers, body]
end

loop do
  client = server.accept
  method, path, _headers, body = read_request(client)
  next unless method

  if method == 'POST' && body && !body.empty?
    begin
      data = JSON.parse(body)
    rescue JSON::ParserError
      data = {}
    end
    message = data.dig('variables', 'message') || 'default'
    response_body = { data: { echo: message } }.to_json
  else
    response_body = manual.to_json
  end

  client.write "HTTP/1.1 200 OK\r\n"
  client.write "Content-Type: application/json\r\n"
  client.write "Content-Length: #{response_body.bytesize}\r\n"
  client.write "\r\n"
  client.write response_body
  client.close
end
