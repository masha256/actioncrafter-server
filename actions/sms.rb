require './workers/twilio_worker'

module Action
  class Sms

    def process(event)
      puts "Scheduling twilio job for event #{event.name}"

      params = event.params
      if params[:to] && params[:message]
        TwilioWorker.perform_async(event.name, params)
      else
        puts "Invalid sms send event - missing to or message"
      end

    end

  end
end
