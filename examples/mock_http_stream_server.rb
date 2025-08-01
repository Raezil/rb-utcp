require 'webrick'
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

server = WEBrick::HTTPServer.new(Port: 4569, AccessLog: [], Logger: WEBrick::Log.new(nil, WEBrick::Log::FATAL))

server.mount_proc '/numbers' do |req, res|
  if req.body && !req.body.empty?
    begin
      data = JSON.parse(req.body)
    rescue JSON::ParserError
      data = {}
    end
    count = (data['count'] || 5).to_i
    res['Content-Type'] = 'application/x-ndjson'
    res.chunked = true
    res.body = Enumerator.new do |y|
      count.times do |i|
        y << { number: i + 1 }.to_json + "\n"
        sleep 0.5
      end
    end
  else
    res['Content-Type'] = 'application/json'
    res.body = manual.to_json
  end
end

trap('INT') { server.shutdown }
server.start
