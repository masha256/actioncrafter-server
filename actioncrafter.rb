

require 'sinatra'
require 'uri'
require 'json'
require 'crack'
require 'sidekiq'
require 'redis'


EVENT_QUEUE='events'


# hand over exception handling to our handlers defined below
disable :show_exceptions
disable :raise_errors
#disable :dump_errors
set :protection, :except => :json_csrf

ENV["REDISTOGO_URL"] ||= "redis://localhost:6379/"
uri = URI.parse(ENV["REDISTOGO_URL"])
REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

# workers
require './workers/event_worker'
require './workers/twilio_worker'



get '/event' do
  unless params[:name]
    halt 400, json_response(false, {}, "Missing event name")
  end

  params['_date'] = Time::now.to_i

  if params[:name] == 'ac_sendsms'
    TwilioWorker.perform_async(params)
  elsif params[:name] == 'ac_twitter'

  else
      REDIS.rpush(EVENT_QUEUE, params.to_json)
  end

  json_response(true)
end


get '/queue/pop' do
  event = REDIS.lpop(EVENT_QUEUE)
  if event
    json_response(true, {:item => JSON.parse(event)})
  else
    json_response(true, {:item => nil})
  end
end

get '/queue/all' do

  list = Array.new

  if params[:save] == '1'
    items = REDIS.lrange(EVENT_QUEUE, 0, -1)
    items.each do |i|
      list.push(JSON.parse(i))
    end
  else
    len = REDIS.llen(EVENT_QUEUE)
    len.times do
      item = REDIS.lpop(EVENT_QUEUE)
      list.push(JSON.parse(item))
    end
  end

  json_response(true, {:items => list, :item_count => list.size})
end




get '/ping' do
  json_response(REDIS.ping == 'PONG')
end


def json_response(status, data = {}, error="")
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


error do
  halt 500, json_response(false, {}, env['sinatra.error'].message)
end

