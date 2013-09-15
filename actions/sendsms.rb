require './workers/twilio_worker'

module Action
  class Sendsms

    def process(event)
      #TwilioWorker.perform_async(event)
      puts "Scheduling twilio job"
    end

  end
end
