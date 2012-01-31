#
# Sends a message to Hastur every so often
#

require_relative "hastur_messenger"

class HasturHeartbeat

  class << self
    attr_accessor :t

    #
    # Stops the heartbeat thread
    #
    def stop
      Thread.kill( HasturHeartbeat.t )
    end

    #
    # Starts a heartbeat for the Hastur client
    #
    def start( interval )
      HasturHeartbeat.t = Thread.start(interval) do |i|
        begin
          loop do
            HasturMessenger.send(HasturClientConfig::HEARTBEAT_ROUTE, "{ \"method\" : \"heartbeat\", \"time\" : \"#{Time.now}\" }")
            sleep(interval)
          end
        rescue Exception => e
          STDERR.puts "Unable to send a heart message => #{e.message} \n\n#{e.backtrace}"
        end
      end
    end
  end
end