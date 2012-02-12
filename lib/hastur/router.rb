require 'ffi-rzmq'
require 'yajl'
require 'multi_json'
require 'uuid'
require 'socket'
require 'termite'

require "hastur/message"
require "hastur/util"

module Hastur
  class Router
    attr_reader :uuid, :errors, :dynamic

    #
    # r = Hastur::Router.new('e315debb-50ba-47a6-9fb4-461757fe1e78')
    #
    def initialize(uuid)
      raise ArgumentError.new "uuid (positional) is required" unless uuid 
      raise ArgumentError.new "uuid must be in 36-byte hex form" unless Hastur::Util.valid_uuid?(uuid)

      @uuid       = uuid
      @route_fds  = {} # hash of fd => [ {route}, {route}, ... ]
      @dynamic    = {} # hash of client_uuid => [socket, [zmq parts]]
      @timestamps = {} # hash of client_uuid => timestamp (float)
      @logger     = Termite::Logger.new
      @poller     = ZMQ::Poller.new
      @stats      = { :to => 0, :from => 0, :to_from => 0, :missed => 0 }
      @errors     = 0
    end

    #
    # Create a routing rule on route :to from socket :src to socket :dest.  This doesn't actually
    # run much except for parameter checking and adding the rule to the internal list.
    #
    # Options:
    #  :to      - either a symbolic route or a route UUID
    #  :src     - ZMQ socket to read from
    #  :dest    - ZMQ socket to write to
    #  :static? - (bool) this route cannot be modified at runtime
    #
    # Examples:
    # r.route :to => :stat, :src => client_router_sock, :dest => stat_sink_sock
    # r.route :to => :stat, :src => client_router_sock, :dest => stats_tap_sock
    # r.route :to => :log,  :src => client_router_sock, :dest => cass_log_sock
    # r.route :to => :log,  :src => client_router_sock, :dest => file_sink_sock
    # r.route(
    #   :to   => :log,
    #   :from => '62780b2f-8d12-4840-9c6e-e89dae8cd322',
    #   :src  => client_router_sock,
    #   :dest => console_debug_sock,
    # )
    #
    #
    def route(opts)
      unless opts[:to] or opts[:from]
        raise ArgumentError.new ":to or :from is required"
      end
        
      raise ArgumentError.new ":src is required"  unless opts.has_key? :src
      raise ArgumentError.new ":dest is required" unless opts.has_key? :dest

      unless opts[:src].kind_of? ZMQ::Socket
        raise ArgumentError.new "Only ZMQ::Sockets are allowed and :src is a #{opts[:src].class}."
      end

      unless opts[:dest].kind_of? ZMQ::Socket
        raise ArgumentError.new "Only ZMQ::Sockets are allowed and :dest is a #{opts[:dest].class}."
      end

      # ZMQ::Poller already checks if it already knows about a socket, so let it handle duplicates
      # only poll for readability in the primary poll, only poll writability once and let it block as needed
      @poller.register_readable opts[:src]

      route = {
        :src     => opts[:src],
        :dest    => opts[:dest],
        :static? => opts[:static?] ? true : false
      }

      if opts[:to] 
        if Hastur.route?(opts[:to])
          route[:to] = Hastur.route_id(opts[:to])
        elsif Hastur::Util.valid_uuid?(opts[:to])
          route[:to] = opts[:to]
        else
          raise ArgumentError.new ":to must be a valid Hastur route (id or symbol) or a 36-byte hex UUID (#{opts[:to]})"
        end
      end

      # :from can never be a symbolic route - it doesn't make any sense
      if opts[:from] and Hastur::Util.valid_uuid?(opts[:from])
        route[:from] = opts[:from]
      end

      # socket fd's are unique inside a process and can be looked up
      # inside the poll loop to get the routes for that socket
      rc = route[:src].getsockopt(ZMQ::FD, val=[])
      src_fd = val[0]
      @route_fds[src_fd] ||= []
      @route_fds[src_fd] << route
    end

    #
    # poll all of the sockets set up via .route() for read and route messages based on those rules
    #
    def poll(zmq_poll_timeout=0.1)
      rc = @poller.poll(zmq_poll_timeout)

      # nothing waiting or socket error, take a hit and make sure we don't spin a CPU
      if rc < 1
        @errors += 1
        sleep zmq_poll_timeout
        return rc
      end

      @poller.readables.each do |socket|
        msg = Hastur::Message.recv(socket)

        # convenience variables
        from = msg.envelope.from
        to   = msg.envelope.to
        time = msg.envelope.timestamp

        # update the list of when a UUID was last seen
        # use client timestamp to avoid problems due to clock skew
        if @timestamps.has_key? from 
          # expire cached zmq_parts every 10 minutes
          if @dynamic.has_key? from and @timestamps[from] < (time - 600)
            dynsock, zmq_parts = @dynamic.delete(from)
            zmq_parts.each { |part| part.close }
          end
        else
          @timestamps[from] = time
        end

        # make a copy of the ZeroMQ routing headers and story by source UUID
        # this is what makes it possible to deliver messages to clients
        if @dynamic[from]
          msg.close_zmq_parts
        else
          @dynamic[from] = [socket, msg.zmq_parts]
        end
        msg.zmq_parts = []

        # use the fd to map back to a route list
        rc = socket.getsockopt(ZMQ::FD, vals=[]) 
        fd = vals[0]

        times_routed = 0
        @route_fds[fd].each do |r|
          # test in the order of popularity
          # simple :to routes without :from matching should be well over 90% of cases, e.g.
          # r.route :to => :stat, :src => client_router_sock, :dest => stat_sink_sock
          if r.has_key? :to and not r.has_key? :from and r[:to] == to
            msg.send(r[:dest])
            @stats[:to] += 1
            times_routed += 1

          # very specific :to and :from exact specification
          # mostly useful for tapping a specific stream from a specific source, e.g.
          # r.route :to => :stat, :from => client_uuid, :src => client_router_sock, :dest => stat_tap_sock
          elsif r.has_key? :to and r.has_key? :from and r[:to] == to and r[:from] == from
            msg.send(r[:dest])
            @stats[:to_from] += 1
            times_routed += 1

          # only match on from, generally expected to be used for client debugging/test replaying, e.g.
          # r.route :from => client_uuid, :src => client_router_sock, :dest => client_tap_sock
          elsif r.has_key? :from and not r.has_key? :to and r[:from] == from
            msg.send(r[:dest])
            @stats[:from] += 1
            times_routed += 1

          else
            @stats[:missed] += 1
            times_routed += 1
          end
        end

        # Messages destined to clients on the ZMQ::ROUTER socket can only be
        # reached via their zeromq-assigned identities.
        # Swap whatever zeromq envelope came with the message for a copy of an envelope
        # captured from inbound clients. It's a bit like ARP.
        # Future: We may eventually want a router broadcast channel for an arp-like "who has" pattern.
        if @dynamic.has_key? to
          # messages are not reusable: copy each message (usually 1) from the cache
          msg.zmq_parts = @dynamic[to][1].map do |original|
            new = ZMQ::Message.new
            new.copy original.pointer
            new
          end
          msg.send(@dynamic[to][0], :final => true)
        end

        # no route match, should not happen really except in integration tests that don't wire everything up
        if times_routed < 1
          # TODO: add a sensible way to set up the error channel
          @logger.warn "unroutable message '#{from}' -> '#{to}': #{msg.to_json}"
        end

        # TODO: write out router stats
      end
    end

    #
    # Free ZMQ::Message parts cached in @dynamic hash.
    #
    def free_dynamic
      @dynamic.keys do |uuid|
        sock, zmq_parts = @dynamic.delete uuid
        zmq_parts.each { |part| part.close }
      end
    end

    #
    # Set the shutdown flag so the run() loop exits cleanly.
    #
    def shutdown
      @running = false
    end

    #
    # run in a loop while .running == true
    #
    def run(zmq_poll_timeout=0.1)
      @running = true
      while @running == true
        poll(zmq_poll_timeout)
      end
      free_dynamic
    end
  end
end