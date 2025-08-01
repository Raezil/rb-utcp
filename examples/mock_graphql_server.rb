require 'webrick'
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

server = WEBrick::HTTPServer.new(Port: 4570, AccessLog: [], Logger: WEBrick::Log.new(nil, WEBrick::Log::FATAL))

server.mount_proc '/graphql' do |req, res|
  res['Content-Type'] = 'application/json'
  if req.request_method == 'POST' && req.body && !req.body.empty?
    begin
      data = JSON.parse(req.body)
    rescue JSON::ParserError
      data = {}
    end
    message = data.dig('variables', 'message') || 'default'
    res.body = { data: { echo: message } }.to_json
  else
    res.body = manual.to_json
  end
end

trap('INT') { server.shutdown }
server.start
