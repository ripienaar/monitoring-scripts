#!/usr/bin/ruby

# A plugin for Nagios that connects to an ActiveMQ instance with the
# ActiveMQ Statistics Plugin[1] enabled to monitor the size of a queue
#
# Report stats for the queue foo.bar with thresholds
#
#    activemq_activemq_queue.rb --queue foo.bar ----queue-warn 10 --queue-crit 20
#
# See --help for full arguments like setting credentials and which
# broker to connect to
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
           :host => "localhost",
           :port => 6163,
           :queue_warn => 100,
           :queue_crit => 500,
           :queue => nil}

opt = OptionParser.new

opt.on("--user USER", "Connect as user") do |f|
    @options[:user] = f
end

opt.on("--password PASSWORD", "Connection password") do |f|
    @options[:password] = f
end

opt.on("--host HOST", "Host to connect to") do |f|
    @options[:host] = f
end

opt.on("--port PORT", Integer, "Port to connect to") do |f|
    @options[:port] = f
end

opt.on("--queue QUEUE.NAME", "What queue to monitor") do |f|
    @options[:queue] = f
end

opt.on("--queue-crit CRIT", Integer, "Critical threshold") do |f|
    @options[:queue_crit] = f
end

opt.on("--queue-warn WARN", Integer, "Warning threshold") do |f|
    @options[:queue_warn] = f
end

opt.parse!

if @options[:queue].nil?
    puts "Please specify a queue name with --queue"
    exit(3)
end

def amqxmldecode(amqmap)
    map = Hash.new

    Document.new(amqmap).root.each_element do |element|
        value = name = nil

        element.each_element_with_text do |e,t|
            name = e.text.to_sym unless name

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

exitcode = 0

begin
    Timeout::timeout(2) do
        conn = Stomp::Connection.open(@options[:user], @options[:password], @options[:host], @options[:port], true)

        conn.subscribe("/topic/statresults", { "transformation" => "jms-map-xml"})

        conn.publish("/queue/ActiveMQ.Statistics.Destination.#{@options[:queue]}", "", {"reply-to" => "/topic/statresults"})

        s = conn.receive.body
        map = amqxmldecode(s)

        if map[:size] >= @options[:queue_crit]
            puts("CRITICAL: ActiveMQ #{@options[:queue]} has #{map[:size]} messages")
            exitcode = 2
        elsif map[:size] >= @options[:queue_warn]
            puts("WARNING: ActiveMQ #{@options[:queue]} has #{map[:size]} messages")
            exitcode = 1
        else
            puts("OK: ActiveMQ #{@options[:queue]} has #{map[:size]} messages")
            exitcode = 0
        end
    end
rescue Exception => e
    puts("UNKNOWN: Failed to get stats: #{e}")
    exitcode = 3
end

exit(exitcode)
