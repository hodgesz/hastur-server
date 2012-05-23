require_relative "../../test_helper"

require "hastur-server/cassandra/schema"

GAUGE_JSON = <<JSON
{
  "type": "gauge",
  "uuid": "91c61ff0-8740-012f-e54a-64ce8f3a9dc2",
  "name": "this.is.a.gauge",
  "value": 37.1,
  "timestamp": 1329858724285438,
  "labels": {
    "a": 1,
    "b": 2
  }
}
JSON

COUNTER_JSON = <<JSON
{
  "type": "counter",
  "uuid": "91c61ff0-8740-012f-e54a-64ce8f3a9dc2",
  "name": "totally.a.counter",
  "value": 5,
  "timestamp": 1329858724285438,
  "labels": {
    "c": 1,
    "d": 2,
    "e": 9
  }
}
JSON

MARK_JSON = <<JSON
{
  "type": "mark",
  "uuid": "91c61ff0-8740-012f-e54a-64ce8f3a9dc2",
  "name": "marky.mark",
  "value": "start",
  "timestamp": 1329858724285438,
  "labels": {
  }
}
JSON

EVENT_JSON = <<JSON
{
  "type": "event",
  "uuid": "91c61ff0-8740-012f-e54a-64ce8f3a9dc2",
  "name": "fake.event.name",
  "timestamp": 1329858724285438,
  "body": "stack trace placeholder",
  "attn": [
    "backlot-oncall",
    "noah@ooyala.com",
    "big Jimmy"
  ],
  "labels": {
  }
}
JSON

REG_PROCESS_JSON = <<JSON
{
  "type": "reg_process",
  "uuid": "91c61ff0-8740-012f-e54a-64ce8f3a9dc2",
  "data": { "a": "b", "c": "d" },
  "timestamp": 1329858724285438,
  "labels": {
  }
}
JSON

FAKE_UUID = "fafafafa-fafa-fafa-fafa-fafafafafafa"
FAKE_UUID2 = "fafafafa-fafa-fafa-fafa-fafafafafaf2"
FAKE_UUID3 = "fafafafa-fafa-fafa-fafa-fafafafafaf3"
NOWISH_TIMESTAMP = 1330000400.to_s

# Row timestamp rounded to nearest 5 minutes
ROW_TS = 1329858600000000

# Row timestamp rounded to nearest hour
ROW_HOUR_TS = 1329858000000000

ROW_DAY_TS = Hastur::Cassandra.send(:time_segment_for_timestamp, ROW_TS, Hastur::Cassandra::ONE_DAY).to_s

class CassandraSchemaTest < Scope::TestCase
  setup do
    @cass_client = mock("Cassandra client")
    @cass_client.stubs(:batch).yields(@cass_client)
    Hastur::Util.stubs(:timestamp).with(nil).returns(NOWISH_TIMESTAMP)
  end

  context "Cassandra message schema" do

    should "insert a gauge into GaugeArchive and StatGauge" do
      json = GAUGE_JSON
      row_key = "#{FAKE_UUID}-#{ROW_TS}"
      colname = "this.is.a.gauge-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE"
      @cass_client.expects(:insert).with(:GaugeArchive, row_key, { colname => json }, {})
      @cass_client.expects(:insert).with(:StatGauge, row_key, { colname => (37.1).to_msgpack }, {})
      @cass_client.expects(:insert).with(:GaugeMetadata, row_key,
                                         { "last_write" => NOWISH_TIMESTAMP,
                                           "last_access" => NOWISH_TIMESTAMP }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "uuid-#{ROW_DAY_TS}", { FAKE_UUID => "" }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "name-#{ROW_DAY_TS}",
                                         { "this.is.a.gauge-11" => "" }, {})
      Hastur::Cassandra.insert(@cass_client, json, "gauge", :uuid => FAKE_UUID)
    end

    should "insert a counter into CounterArchive and StatCounter" do
      json = COUNTER_JSON
      row_key = "#{FAKE_UUID}-#{ROW_TS}"
      colname = "totally.a.counter-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE"
      @cass_client.expects(:insert).with(:CounterArchive, row_key, { colname => json }, {})
      @cass_client.expects(:insert).with(:StatCounter, row_key, { colname => (5).to_msgpack }, {})
      @cass_client.expects(:insert).with(:CounterMetadata, row_key,
                                         { "last_write" => NOWISH_TIMESTAMP,
                                           "last_access" => NOWISH_TIMESTAMP }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "uuid-#{ROW_DAY_TS}", { FAKE_UUID => "" }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "name-#{ROW_DAY_TS}",
                                         { "totally.a.counter-12" => "" }, {})
      Hastur::Cassandra.insert(@cass_client, json, "counter", :uuid => FAKE_UUID)
    end

    should "insert a mark into MarkArchive and StatMark" do
      json = MARK_JSON
      row_key = "#{FAKE_UUID}-#{ROW_HOUR_TS}"
      colname = "marky.mark-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE"
      @cass_client.expects(:insert).with(:MarkArchive, row_key, { colname => json }, {})
      @cass_client.expects(:insert).with(:StatMark, row_key, { colname => ("start").to_msgpack }, {})
      @cass_client.expects(:insert).with(:MarkMetadata, row_key,
                                         { "last_write" => NOWISH_TIMESTAMP,
                                           "last_access" => NOWISH_TIMESTAMP }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "uuid-#{ROW_DAY_TS}", { FAKE_UUID => "" }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "name-#{ROW_DAY_TS}",
                                         { "marky.mark-10" => "" }, {})
      Hastur::Cassandra.insert(@cass_client, json, "mark", :uuid => FAKE_UUID)
    end

    should "insert an event into EventArchive" do
      json = EVENT_JSON
      row_key = "#{FAKE_UUID}-1329782400000000"  # Time rounded down to day
      colname = "fake.event.name-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE"
      @cass_client.expects(:insert).with(:EventArchive, row_key, { colname => json }, {})
      @cass_client.expects(:insert).with(:EventMetadata, row_key,
                                         { "last_write" => NOWISH_TIMESTAMP,
                                           "last_access" => NOWISH_TIMESTAMP }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "uuid-#{ROW_DAY_TS}", { FAKE_UUID => "" }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "name-#{ROW_DAY_TS}",
                                         { "fake.event.name-1" => "" }, {})
      Hastur::Cassandra.insert(@cass_client, json, "event", :uuid => FAKE_UUID)
    end

    should "insert a reg_process into RegProcessArchive" do
      json = REG_PROCESS_JSON
      row_key = "#{FAKE_UUID}-1329782400000000"  # Time rounded down to day
      colname = "\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE"
      @cass_client.expects(:insert).with(:RegProcessArchive, row_key, { colname => json }, {})
      @cass_client.expects(:insert).with(:RegProcessMetadata, row_key,
                                         { "last_write" => NOWISH_TIMESTAMP,
                                           "last_access" => NOWISH_TIMESTAMP }, {})
      @cass_client.expects(:insert).with(:LookupByKey, "uuid-#{ROW_DAY_TS}", { FAKE_UUID => "" }, {})
      Hastur::Cassandra.insert(@cass_client, json, "reg_process", :uuid => FAKE_UUID)
    end

    should "query a gauge from StatGauge" do
      @cass_client.expects(:multi_get).with(:StatGauge, [ "#{FAKE_UUID}-#{ROW_TS}" ],
                                            :count => 10_000,
                                            :finish => "this.is.a.gauge-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE",
                                            :start => "this.is.a.gauge-\x00\x04\xB9\x7F\xDC\xDC\xCC\x00").
        returns({})
      @cass_client.expects(:insert).with(:GaugeMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "gauge",
                                  1329858724285438, 1329858724285440,
                                  :name => "this.is.a.gauge", :value_only => true)
      assert_equal({}, out)
    end

    should "query a counter from StatCounter" do
      @cass_client.expects(:multi_get).with(:StatCounter, [ "#{FAKE_UUID}-#{ROW_TS}" ],
                                            :count => 10_000,
                                            :finish => "some.counter-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE",
                                            :start => "some.counter-\x00\x04\xB9\x7F\xDC\xDC\xCC\x00").
        returns({})
      @cass_client.expects(:insert).with(:CounterMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "counter",
                                  1329858724285438, 1329858724285440,
                                  :name => "some.counter", :value_only => true)
      assert_equal({}, out)
    end

    should "query a mark from StatMark" do
      @cass_client.expects(:multi_get).with(:StatMark, [ "#{FAKE_UUID}-#{ROW_HOUR_TS}" ],
                                            :count => 10_000,
                                            :finish => "this.is.a.mark-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE",
                                            :start => "this.is.a.mark-\x00\x04\xB9\x7F\xDC\xDC\xCC\x00").
        returns({})
      @cass_client.expects(:insert).with(:MarkMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "mark",
                                  1329858724285438, 1329858724285440,
                                  :name => "this.is.a.mark", :value_only => true)
      assert_equal({}, out)
    end

    should "query a gauge from GaugeArchive" do
      @cass_client.expects(:multi_get).with(:GaugeArchive, [ "#{FAKE_UUID}-#{ROW_TS}" ],
                                            :count => 10_000,
                                            :finish => "this.is.a.gauge-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE",
                                            :start => "this.is.a.gauge-\x00\x04\xB9\x7F\xDC\xDC\xCC\x00").
        returns({})
      @cass_client.expects(:insert).with(:GaugeMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "gauge",
                                       1329858724285438, 1329858724285440, :name => "this.is.a.gauge")
      assert_equal({}, out)
    end

    should "query an event from EventArchive" do
      @cass_client.expects(:multi_get).with(:EventArchive, [ "#{FAKE_UUID}-1329782400000000" ],
                                            :count => 10_000).
        returns({})
      @cass_client.expects(:insert).with(:EventMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "event", 1329858724285438, 1329858724285440)
      assert_equal({}, out)
    end

    should "query an event from EventArchive with multiple client UUIDs" do
      day_ts = "1329782400000000"
      @cass_client.expects(:multi_get).with(:EventArchive,
                                            [ "#{FAKE_UUID}-#{day_ts}",
                                              "#{FAKE_UUID2}-#{day_ts}",
                                              "#{FAKE_UUID3}-#{day_ts}" ],
                                            :count => 10_000).
        returns({})
      @cass_client.expects(:insert).with(:EventMetadata, "#{FAKE_UUID}-#{day_ts}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      @cass_client.expects(:insert).with(:EventMetadata, "#{FAKE_UUID2}-#{day_ts}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      @cass_client.expects(:insert).with(:EventMetadata, "#{FAKE_UUID3}-#{day_ts}",
                                         { "last_access" => NOWISH_TIMESTAMP}, {})
      out = Hastur::Cassandra.get(@cass_client, [ FAKE_UUID, FAKE_UUID2, FAKE_UUID3 ], "event",
                                  1329858724285438, 1329858724285440)
      assert_equal({}, out)
    end

    context "Filtering stats from Cassandra representation" do
      setup do
        @coded_ts_37 = [1329858724285437].pack("Q>")
        @coded_ts_38 = [1329858724285438].pack("Q>")
        @coded_ts_39 = [1329858724285439].pack("Q>")
        @coded_ts_40 = [1329858724285440].pack("Q>")
        @coded_ts_41 = [1329858724285441].pack("Q>")
      end

      should "prepare a stat from Cassandra representation with get" do
        @cass_client.expects(:multi_get).with(:StatMark, [ "#{FAKE_UUID}-#{ROW_HOUR_TS}" ],
                                              :count => 10_000,
                                              :finish => "this.is.a.mark-\x00\x04\xB9\x7F\xDC\xDC\xCB\xFE",
                                              :start => "this.is.a.mark-\x00\x04\xB9\x7F\xDC\xDC\xCC\x00").
          returns({
                    "uuid1-1234567890" => { },   # Delete row with empty hash
                    "uuid2-0987654321" => nil,   # Delete row with nil
                    "uuid3-1234500000" => {
                      "this.is.a.mark-#{@coded_ts_37}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_38}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_39}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_40}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_41}" => "".to_msgpack,
                    }
                  })
        @cass_client.expects(:insert).with(:MarkMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                           { "last_access" => NOWISH_TIMESTAMP}, {})
        out = Hastur::Cassandra.get(@cass_client, FAKE_UUID, "mark",
                                    1329858724285438, 1329858724285440,
                                    :name => "this.is.a.mark", :value_only => true)

        assert_equal({
                       "uuid3" => {
                         "this.is.a.mark" => {
                           1329858724285438 => "",
                           1329858724285439 => "",
                           1329858724285440 => "",
                         }
                       }
                     }, out)
      end

      should "prepare stats from Cassandra representation with get_all_stats" do
        @cass_client.expects(:multi_get).with(:StatMark, [ "#{FAKE_UUID}-#{ROW_HOUR_TS}" ], :count => 10_000).
          returns({
                    "uuid1-1234567890" => { },   # Delete row with empty hash
                    "uuid2-0987654321" => nil,   # Delete row with nil
                    "uuid3-1234500000" => {
                      "this.is.a.mark-#{@coded_ts_37}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_38}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_39}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_40}" => "".to_msgpack,
                      "this.is.a.mark-#{@coded_ts_41}" => "".to_msgpack,
                      "this.mark-#{@coded_ts_37}" => "".to_msgpack,
                      "this.mark-#{@coded_ts_38}" => "".to_msgpack,
                      "this.mark-#{@coded_ts_40}" => "".to_msgpack,
                      "this.mark-#{@coded_ts_41}" => "".to_msgpack,
                    }
                  })
        @cass_client.expects(:multi_get).with(:StatGauge, [ "#{FAKE_UUID}-#{ROW_TS}" ], :count => 10_000).
          returns({})
        @cass_client.expects(:multi_get).with(:StatCounter, [ "#{FAKE_UUID}-#{ROW_TS}" ], :count => 10_000).
          returns({})
        @cass_client.expects(:insert).with(:MarkMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                           { "last_access" => NOWISH_TIMESTAMP}, {})
        @cass_client.expects(:insert).with(:GaugeMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                           { "last_access" => NOWISH_TIMESTAMP}, {})
        @cass_client.expects(:insert).with(:CounterMetadata, "#{FAKE_UUID}-#{ROW_DAY_TS}",
                                           { "last_access" => NOWISH_TIMESTAMP}, {})
        out = Hastur::Cassandra.get_all_stats(@cass_client, FAKE_UUID,
                                              1329858724285438, 1329858724285440,
                                              :value_only => true)

        # get_all_stats filters rows by date
        assert_equal({
                       "uuid3" => {
                         "this.is.a.mark" => {
                           1329858724285438 => "",
                           1329858724285439 => "",
                           1329858724285440 => "",
                         },
                         "this.mark" => {
                           1329858724285438 => "",
                           1329858724285440 => "",
                         }
                       }
                     }, out)
      end

    end
  end
end
