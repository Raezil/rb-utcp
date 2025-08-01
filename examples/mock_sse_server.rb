require 'webrick'
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

server = WEBrick::HTTPServer.new(Port: 4568, AccessLog: [], Logger: WEBrick::Log.new(nil, WEBrick::Log::FATAL))

server.mount_proc '/events' do |req, res|
  if req['Accept'].to_s.include?('text/event-stream')
    res['Content-Type'] = 'text/event-stream'
    res.chunked = true
    res.body = Enumerator.new do |y|
      5.times do |i|
        y << "data: #{ { number: i + 1 }.to_json }\n\n"
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
