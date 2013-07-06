
class EventWorker
  include Sidekiq::Worker


  def perform(event)

    puts "Performing event " + event['name']

  end


end