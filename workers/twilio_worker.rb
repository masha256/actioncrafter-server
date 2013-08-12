
require 'twilio-ruby'

class TwilioWorker
  include Sidekiq::Worker

  TWILIO = Twilio::REST::Client.new('AC2738c42b6d6a978bb08219565aa2385c', '31bfaaf56b068e1f17de3a41d66178ac')


  def perform(event)

    puts "Performing twilio event " + event['name']

    TWILIO.account.sms.messages.create(
        :from => '+19162356999',
        :to => params[:to],
        :body => params[:message]
    )

  end


end