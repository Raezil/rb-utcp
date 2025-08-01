require 'socket'
require 'json'

manual = {
  tools: [
    {
      name: 'numbers',
      description: 'Stream numbers as NDJSON',
      input_schema: { type: 'object', properties: { count: { type: 'integer' } }, required: ['count'] },
      output_schema: { type: 'array', items: { type: 'integer' } }
    }
  ]
}

server = TCPServer.new(4569)
puts 'Stream server listening on http://localhost:4569'

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

  if body && !body.empty?
    begin
      data = JSON.parse(body)
    rescue JSON::ParserError
      data = {}
    end
    count = (data['count'] || 5).to_i
    client.write "HTTP/1.1 200 OK\r\n"
    client.write "Content-Type: application/x-ndjson\r\n"
    client.write "\r\n"
    count.times do |i|
      client.write({ number: i + 1 }.to_json + "\n")
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
