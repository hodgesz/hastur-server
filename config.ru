require "hastur-server/service/retrieval"
require "hastur-rack"

HASTUR_CASSANDRA_LIST="/opt/hastur/conf/cassandra-servers.txt"

# defined on most of our Hastur boxes via hastur-deploy
cassandra_servers = []

if File.exists? HASTUR_CASSANDRA_LIST
  File.foreach(HASTUR_CASSANDRA_LIST) do |line|
    line.chomp!
    line.gsub(/\s+#.*$/, '')
    cassandra_servers << line unless line.empty?
  end
elsif ENV['HASTUR_CASSANDRA_LIST']
  cassandra_servers = ENV['HASTUR_CASSANDRA_LIST'].split(':').map(&:strip)
else
  cassandra_servers = [ '127.0.0.1:9160' ]
end

use Hastur::Rack, "hastur.retrieval"

run Hastur::Service::Retrieval.new cassandra_servers
