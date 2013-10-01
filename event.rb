
require 'uri'

module Actioncrafter
  class Event

    attr_accessor :name, :params


    def initialize(evt)

      if evt.is_a?(String)
        evt = from_string(evt)
      end

      p = evt.dup

      @name=p.delete(:name)
      @params = p

    end

    def as_hash
      e = {:name => name}
      e.merge!(params)
    end

    def to_json
      as_hash.to_json
    end


    :private

    def from_string(string)

      evt = Hash.new
      string.split('&').each do |p|
        k, v = p.split('=').map do |i|
          URI.decode(i.gsub(/\+/, ' '))
        end
        evt[k.to_sym] = v
      end

      evt
    end



  end
end