#!/usr/bin/ruby

# A plugin for cacti that connects to an ActiveMQ instance with the
# ActiveMQ Statistics Plugin[1] enabled to fetch stats about the broker
# and about queues
#
# Report stats for the queue foo.bar
#
#    activemq-cacti-plugin.rb --report foo.bar
#
# Report stats for the broker
#
#    activemq-cacti-plugin.rb --report broker
#
# See --help for full arguments like setting credentials and which
# broker to connect to
#
# Multiple brokers can be specified with the --host argument, in
# that case the user/pass/port on them all should be the same it
# will then attempt to connect to them all till a connection is made
# this is for active/passive clusters
#
# R.I.Pienaar <rip@devco.net>
# Apache 2.0 Licence
#
# [1] http://activemq.apache.org/statisticsplugin.html
require 'rexml/document'
require 'rubygems'
require 'optparse'
require 'timeout'
require 'stomp'
require 'pp'

include REXML

@options = {:user => "nagios",
           :password => nil,
           :host => nil,
           :port => 6163,
           :mode => :broker}

opt = OptionParser.new

opt.on("--user USER", "Connect as user") do |f|
  @options[:user] = f
end

opt.on("--password PASSWORD", "Connection password") do |f|
  @options[:password] = f
end

opt.on("--host HOST", "Host to connect to") do |f|
  if @options[:host]
    @options[:host] << f
  else
    @options[:host] = [f]
  end
end

opt.on("--port PORT", Integer, "Port to connect to") do |f|
  @options[:port] = f
end

opt.on("--report [broker|queue.name]", "What to report broker or queue name") do |f|
  case f
    when "broker"
      @options[:mode] = :broker
    else
      @options[:mode] = f
  end
end

opt.parse!

if @options[:host].nil?
  puts "CRITICAL: No host to monitor supplied"
  exit 2
end

def amqxmldecode(amqmap)
  map = Hash.new

  Document.new(amqmap).root.each_element do |element|
    value = name = nil

    element.each_element_with_text do |e,t|
      name = e.text unless name

      if name
        case e.name
          when "string"
            map[name] = e.text

          when /int|long/
            map[name] = e.text.to_i

          when "double"
            map[name] = e.text.to_f

          else
            raise("Unknown data type #{e.name}")
        end
      end
    end
  end

  map
end

# dont spew any stuff to stderr
class EventLogger
  def on_miscerr(params=nil); end
  def on_connectfail(params=nil); end
end

begin
  Timeout::timeout(2) do
    hostname = `hostname`.chomp

    connection = {:hosts => [], :logger => EventLogger.new}

    @options[:host].each do |host|
      connection[:hosts] << {:host => host, :port => @options[:port], :login => @options[:user], :passcode => @options[:password]}
    end

    conn = Stomp::Connection.open(connection)

    conn.subscribe("/topic/nagios.statresults.#{hostname}", { "transformation" => "jms-map-xml"})

    if @options[:mode] == :broker
      conn.publish("/queue/ActiveMQ.Statistics.Broker", "", {"reply-to" => "/topic/nagios.statresults.#{hostname}"})
    else
      conn.publish("/queue/ActiveMQ.Statistics.Destination.#{@options[:mode]}", "", {"reply-to" => "/topic/nagios.statresults.#{hostname}"})
    end

    s = conn.receive.body
    conn.disconnect

    map = amqxmldecode(s)

    map.each_pair do |k, v|
      next if k.match(/\+/)

      print("#{k}:#{v} ")
    end

    puts
  end
rescue Exception => e
  puts("Failed to get stats: #{e}")
end

