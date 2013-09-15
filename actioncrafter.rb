

require 'sinatra'
require 'uri'
require 'json'
require 'crack'
require 'sidekiq'
require 'redis'


# hand over exception handling to our handlers defined below
disable :show_exceptions
disable :raise_errors
#disable :dump_errors
set :protection, :except => :json_csrf

API_KEYS = 'api_keys'

ENV["REDISTOGO_URL"] ||= "redis://localhost:6379/"
uri = URI.parse(ENV["REDISTOGO_URL"])
REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

# workers
require './workers/event_worker'

# actions
require './actions'


get '/action' do
  check_api_key(params[:key])

  unless params[:name]
    halt 400, json_response(false, {}, "Missing action name")
  end

  source = params[:source] || 'default'
  event = params.dup

  # clean up sinatra default keys
  event.delete('splat')
  event.delete('captures')
  event.delete('key')

  event['_date'] = Time::now.to_i


  begin
    klass = Object.const_get('Action').const_get(params[:name].capitalize)
    action = klass.new
    action.process(event)
  rescue
    puts "No class found for action #{params[:name]}, queuing instead"

    REDIS.rpush(queue_name(source, params[:key]), event.to_json)
  end


  json_response(true)
end


get '/queue/:queue/event' do

  check_api_key(params[:key])

  unless params[:name]
    halt 400, json_response(false, {}, "Missing event name")
  end

  params['_date'] = Time::now.to_i

  if params[:name] == 'ac_sendsms'
    TwilioWorker.perform_async(params)
  elsif params[:name] == 'ac_twitter'

  else
      event = params.dup

      # clean up sinatra default keys
      event.delete('splat')
      event.delete('captures')
      event.delete('key')
      event.delete('queue')

      REDIS.rpush(queue_name(params[:queue], params[:key]), event.to_json)
  end

  json_response(true)
end


get '/queue/:queue/pop' do

  check_api_key(params[:key])

  event = REDIS.lpop(queue_name(params[:queue], params[:key]))
  if event
    json_response(true, {:item => JSON.parse(event)})
  else
    json_response(true, {:item => nil})
  end
end

get '/queue/:queue/all' do

  check_api_key(params[:key])

  list = Array.new

  if params[:save] == '1'
    items = REDIS.lrange(queue_name(params[:queue], params[:key]), 0, -1)
    items.each do |i|
      list.push(JSON.parse(i))
    end
  else
    len = REDIS.llen(queue_name(params[:queue], params[:key]))
    len.times do
      item = REDIS.lpop(queue_name(params[:queue], params[:key]))
      list.push(JSON.parse(item))
    end
  end

  json_response(true, {:items => list, :item_count => list.size})
end




get '/ping' do
  json_response(REDIS.ping == 'PONG')
end


def json_response(status, data = {}, error='')
  content_type :json
  if error.empty?
    result =  {:success => status}.merge(data).to_json
  else
    result =  {:success => status, :error => error}.merge(data).to_json
  end

  if params[:callback]
    params[:callback]+'('+result+');'
  else
    result
  end

end

def queue_name(name, key)
  if name && name.match(/^[a-zA-Z0-9\-_]{2,32}$/)
    key+'_'+name
  else
    raise 'Invalid queue name'
  end
end

def check_api_key(key)
  unless REDIS.hexists(API_KEYS, key)
    raise 'Invalid API key'
  end
  REDIS.hincrby(API_KEYS, key, 1)
end



error do
  halt 500, json_response(false, {}, env['sinatra.error'].message)
end

