require 'webrick'
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

server = WEBrick::HTTPServer.new(Port: 9999, AccessLog: [], Logger: WEBrick::Log.new(nil, WEBrick::Log::FATAL))

server.mount_proc '/' do |req, res|
  res['Content-Type'] = 'application/json'
  if req.request_method == 'POST' && req.body && !req.body.empty?
    begin
      data = JSON.parse(req.body)
    rescue JSON::ParserError
      data = {}
    end
    res.body = { message: data['message'] }.to_json
  else
    res.body = manual.to_json
  end
end

trap('INT') { server.shutdown }
server.start
