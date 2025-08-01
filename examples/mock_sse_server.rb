require 'socket'
require 'json'

manual = {
  tools: [
    {
      name: 'stream',
      description: 'Stream numbers via SSE',
      output_schema: { type: 'object', properties: { number: { type: 'integer' } } }
    }
  ]
}

server = TCPServer.new(4568)
puts 'SSE server listening on http://localhost:4568'

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
  method, path, headers, body = read_request(client)
  next unless method

  if headers['Accept'].to_s.include?('text/event-stream')
    client.write "HTTP/1.1 200 OK\r\n"
    client.write "Content-Type: text/event-stream\r\n"
    client.write "Cache-Control: no-cache\r\n"
    client.write "\r\n"
    5.times do |i|
      client.write "data: #{ { number: i + 1 }.to_json }\n\n"
      client.flush
      sleep 0.5
    end
  else
    body_text = manual.to_json
    client.write "HTTP/1.1 200 OK\r\n"
    client.write "Content-Type: application/json\r\n"
    client.write "Content-Length: #{body_text.bytesize}\r\n"
    client.write "\r\n"
    client.write body_text
  end
  client.close
end
