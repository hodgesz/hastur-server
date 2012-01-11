#
# A listener that processes REGISTER_SERVICE events
#

require "#{File.dirname(__FILE__)}/hastur_listener"

class HasturServiceListener < HasturListener
  def initialize(port, type)
    super(port, type)
  end

  #
  # Processes a register service request.
  #
  def process_message(msg)
    begin
      msg = JSON.parse(msg)
      # TODO(viet): put this message on the STOMP mq

    rescue Exception => e
      STDERR.puts "Unable to process the message."
      STDERR.puts e.message
    end
  end
end
