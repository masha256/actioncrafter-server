require 'uri'
require 'json'
require 'crack'
require 'sidekiq'
require 'redis'
require 'em-websocket'
require './workers'
require './actions'
require './event'


API_KEYS = 'api_keys'

ENV["REDISTOGO_URL"] ||= "redis://localhost:6379/"
uri = URI.parse(ENV["REDISTOGO_URL"])
REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

ACTIONS_CHANNEL_PREFIX = 'actions'

CONNECTIONS = {}
CLIENTS = {}


def check_api_key(key)
  REDIS.hexists(API_KEYS, key)
  #REDIS.hincrby(API_KEYS, key, 1)
end

def parse_message(msg)
  message = JSON.parse(msg)
end


def handle_websocket_message(msg, ws)

  command, data = msg.split(' ', 2)

  if command == 'action'

    conn = CONNECTIONS[ws]

    channel, evt = data.split(' ', 2)

    event = Actioncrafter::Event.new(evt)

    begin
      klass = Object.const_get('Action').const_get(channel.capitalize)
      action = klass.new
      action.process(e)
    rescue Exception => e

      if e
        puts "Exception: " + e.to_s
      end
      redis_channel = ACTIONS_CHANNEL_PREFIX+':'+conn[:key]+':'+channel

      puts "No class found for channel #{channel}, publishing to #{redis_channel} instead"

      REDIS.publish(redis_channel, event.to_json)
    end


  elsif command == 'subscribe'

    conn = CONNECTIONS[ws]

    data.split(',').each do |c|
      puts "Subscribed client to channel #{c}"
      conn[:channels].push(c)
    end

  elsif command == 'unsubscribe'

    conn = CONNECTIONS[ws]

    data.split(',').each do |c|
      puts "Unsubscribed client from channel #{c}"
      conn[:channels].delete(c)
    end

  end

end




Thread.new do
  puts "Redis thread started, subscribing to events"

  begin

    redis_listener = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
    redis_listener.psubscribe(ACTIONS_CHANNEL_PREFIX+':*') do |on|
      on.pmessage do |pattern, chan, msg|
        puts "Got redis message #{msg} from chan #{chan}"

        junk, key, channel = chan.split(':', 3)

        sockets = CLIENTS[key]
        if sockets
          sockets.each do |ws|

            conn = CONNECTIONS[ws]

            if conn[:channels].include?(channel)
              ws.send(msg)
              puts "Sent message to websocket client"
            end

          end
        else
          puts "No connected sockets for key #{key}"
        end

      end
    end

  rescue Exception => e
    puts "Exception in redis thread: " + e
  end

end


Thread.new do
  loop do
    CONNECTIONS.each_key do |ws|
      ws.ping
    end
    sleep(10)
  end
end


puts "Starting websocket server"


EM.run do
  EM::WebSocket.start(:host => "0.0.0.0", :port => 8080, :debug => false) do |ws|

    ws.onopen do |handshake|

      params = handshake.query
      key = params['key']

      puts "Opening connection for key #{key}"

      if check_api_key(key)

        CONNECTIONS[ws] = {:connected => true,
                           :ws => ws,
                           :channels => [],
                           :key => key}
        if CLIENTS[key]
          CLIENTS[key].push(ws)
        else
          CLIENTS[key] = [ws]
        end

        puts "Connection open successful for key #{key}"
      else
        ws.close(4000, 'Invalid API key')
      end

    end


    ws.onclose do
      puts "Connection closed"

      conn = CONNECTIONS[ws]
      if conn

        sockets = CLIENTS[conn[:key]]
        if sockets
          sockets.delete(ws)
        end

        CONNECTIONS.delete(ws)
      end
    end

    ws.onmessage do |msg|
      puts "Received message: #{msg}"
      conn = CONNECTIONS[ws]
      if conn && conn[:connected]
        handle_websocket_message(msg, ws)
      else
        puts "Message received on unauthorized connection"
      end

    end

    ws.onerror do |e|
      puts "Got error #{e.message}"
    end

  end
end


