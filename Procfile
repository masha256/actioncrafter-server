web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
sidekiq: bundle exec sidekiq -C sidekiq.yml -q default -c 10