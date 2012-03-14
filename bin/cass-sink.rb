#!/usr/bin/env ruby
require "trollop"
require "hastur-server/zmq_utils"
require "hastur-server/message"
require "hastur-server/sink/cassandra_schema"

opts = Trollop::options do
  banner "Creates a Cassandra keyspace\n\nOptions:"
  opt :cassandra, "Cassandra URI(s)",       :default => ["127.0.0.1:9160"],        :type => :strings,
                                                                                   :multi => true
  opt :sinks,     "Router sink URI(s)",     :default => ["tcp://127.0.0.1:8127"],  :type => :strings,
                                                                                   :multi => true
  opt :acks_to,   "Router ack URI(s)",      :default => ["tcp://127.0.0.1:8134"],  :type => :strings,
                                                                                   :multi => true
  opt :keyspace,  "Keyspace",               :default => "Hastur",                  :type => String
  opt :hwm,       "ZMQ message queue size", :default => 1,                         :type => :int
end

ctx = ZMQ::Context.new

msg_socket = Hastur::ZMQUtils.connect_socket(ctx, ::ZMQ::PULL, opts[:sinks].flatten)
ack_socket = Hastur::ZMQUtils.connect_socket(ctx, ::ZMQ::PUSH, opts[:acks_to].flatten)

puts "Connecting to Cassandra at #{opts[:cassandra].flatten.inspect}"
client = Cassandra.new(opts[:keyspace], opts[:cassandra].flatten)
client.default_write_consistency = 2  # Initial default: 1

@running = true
%w(INT TERM KILL).each do | sig |
  Signal.trap(sig) do
    @running = false
    Signal.trap(sig, "DEFAULT")
  end
end

while @running do
  begin
    puts "Receiving..."
    message = Hastur::Message.recv(msg_socket)
    envelope = message.envelope
    uuid = message.envelope.from
    route = message.type_symbol.to_s
    puts "[#{route}] - #{message.payload}"
    Hastur::Cassandra.insert(client, message.payload, route, :uuid => uuid)
    envelope.to_ack.send(ack_socket) if envelope.ack?
  rescue Exception => e
    puts e.message
    puts e.backtrace
  end
end

STDERR.puts "Exited!"