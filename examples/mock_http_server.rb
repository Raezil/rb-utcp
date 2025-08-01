require 'socket'
require 'json'

manual = {
  tools: [
    {
      name: 'echo',
      description: 'Echo the provided message',
      input_schema: { type: 'object', properties: { message: { type: 'string' } }, required: ['message'] },
      output_schema: { type: 'string' }
    }
  ]
}

server = TCPServer.new(4567)
puts 'HTTP server listening on http://localhost:4567'

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

  response_body = if body && !body.empty?
                    begin
                      data = JSON.parse(body)
                    rescue JSON::ParserError
                      {}
                    end
                    { message: data['message'] }.to_json
                  else
                    manual.to_json
                  end

  client.write "HTTP/1.1 200 OK\r\n"
  client.write "Content-Type: application/json\r\n"
  client.write "Content-Length: #{response_body.bytesize}\r\n"
  client.write "\r\n"
  client.write response_body
  client.close
end
