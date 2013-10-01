require 'faye/websocket'
require 'eventmachine'

EM.run {
  ws = Faye::WebSocket::Client.new('ws://localhost:8081?key=121212')

  ws.on :open do |event|
    p [:open]
    ws.send('Hello, world!')
    ws.send('Hello, again!')
  end

  ws.on :message do |event|
    p [:message, event.data]

    if event.data == 'event1'
      puts "Got event1"
    end

    puts "Data is #{event.inspect}"

  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    ws = nil
  end
}