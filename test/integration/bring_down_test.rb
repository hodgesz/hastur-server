#!/usr/bin/env ruby

require 'multi_json'
require 'minitest/autorun'

require_relative "./integration_test_helper"

require 'hastur'
require 'hastur-server/message'

require 'nodule/cassandra'
require 'nodule/console'
require 'nodule/process'
require 'nodule/topology'
require 'nodule/unixsocket'
require 'nodule/zeromq'
require 'nodule/util'

class BringDownTest < MiniTest::Unit::TestCase
private
  def hb_in_cassandra?(uuid, key)
    hb = Hastur::Cassandra.get @cass, uuid, "hb_process", @start_ts, @end_ts
    refute_nil hb
    assert hb.has_key?(key)
  end

  def send_heartbeats
    hastur_proxy @agent_udp_port1, :heartbeat, @heartbeat_agent1
    hastur_proxy @agent_udp_port2, :heartbeat, @heartbeat_agent2
  end

public
  def setup
    set_test_alarm(100) # helper

    @agent_udp_port1 = Nodule::Util.random_udp_port
    @agent_udp_port2 = Nodule::Util.random_udp_port
    @heartbeat_agent1 = "heartbeat-agent1"
    @heartbeat_agent2 = "heartbeat-agent2"
    @start_ts         = Hastur::Util.timestamp
    @end_ts           = @start_ts + 150_000_000
    @cf               = "HBProcessArchive"

    @topology = Nodule::Topology.new(
      :greenio       => Nodule::Console.new(:fg => :green),
      :redio         => Nodule::Console.new(:fg => :red),
      :cyanio        => Nodule::Console.new(:fg => :cyan),
      :router        => Nodule::ZeroMQ.new(:uri => :gen),
      :firehose      => Nodule::ZeroMQ.new(:uri => :gen),
      :return        => Nodule::ZeroMQ.new(:uri => :gen, :connect => ZMQ::PUSH),
      :cassandra     => Nodule::Cassandra.new(:keyspace => "Hastur", :verbose => :greenio),
      :coresvc       => Nodule::Process.new(
        HASTUR_CORE_BIN,
        '--uuid',          R1UUID,
        '--router',        :router,
        '--firehose',      :firehose,
        '--return',        :return,
        '--cassandra',     :cassandra,
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio,
      ),
      :agent1svc    => Nodule::Process.new(
        HASTUR_AGENT_BIN,
        '--uuid',         A1UUID,
        '--router',       :router,
        '--ack-timeout',  1,
        '--heartbeat',    300,
        '--port',         @agent_udp_port1,
        '--no-agent-stats',
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio,
      ),
      :agent2svc    => Nodule::Process.new(
        HASTUR_AGENT_BIN,
        '--uuid',         A2UUID,
        '--router',       :router,
        '--ack-timeout',  1,
        '--heartbeat',    300,
        '--port',         @agent_udp_port2,
        '--no-agent-stats',
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio,
      ),
    )
    # start cassandra
    @topology.start :cassandra
    create_all_column_families(@topology[:cassandra]) # helper
    # start everything else but the scheduler
    @topology.start_all
    # wait for the row to show up in Cassandra
    @cass = @topology[:cassandra].client
    wait_for_cassandra_rows @cass, "RegAgentArchive", 1, 30, true
  end

  def teardown
    @topology.stop_all
  end

  def test_bring_down
    # send heartbeat to both agents
    send_heartbeats

    # wait for the row to show up in Cassandra
    wait_for_cassandra_rows(@cass, @cf, 2, 30) do
      flunk "Gave up waiting for heartbeats in cassandra."
    end

    hb_in_cassandra? A1UUID, @heartbeat_agent1
    hb_in_cassandra? A2UUID, @heartbeat_agent2

    # shut an agent down
    @topology.stop :agent2svc
    sleep 5

    send_heartbeats

    wait_for_cassandra_rows @cass, @cf, 3, 30, true

    assert_equal 3, cassandra_cf_value_count(@cass, @cf)

    @topology.start :agent2svc

    wait_for_cassandra_rows @cass, @cf, 7, 30, true

    # resend heartbeats to both agents
    send_heartbeats

    # ensure that both heartbeats were received
    wait_for_cassandra_rows @cass, @cf, 6, 30, true
  end
end
