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
# Defaults:
#
#   host:       n/a
#   port:       6163
#   user:       nagios
#   queue warn: 100
#   queue crit: 500
#   mem warn    50
#   mem crit    75
#
# R.I.Pienaar <rip@devco.net>
# Apache 2.0 License
#
# [1] http://activemq.apache.org/statisticsplugin.html
require 'rexml/document'
require 'rubygems'
require 'optparse'
require 'timeout'
require 'stomp'

include REXML

@options = {:user => "nagios",
           :password => nil,
           :host => nil,
           :port => 6163,
           :queue_warn => 100,
           :queue_crit => 500,
           :memory_percent_warn => 50,
           :memory_percent_crit => 75,
           :queue => nil}

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

opt.on("--queue QUEUE.NAME", "What queue to monitor") do |f|
    @options[:queue] = f
end

opt.on("--queue-crit CRIT", Integer, "Critical queue size") do |f|
    @options[:queue_crit] = f
end

opt.on("--queue-warn WARN", Integer, "Warning queue size") do |f|
    @options[:queue_warn] = f
end

opt.on("--mem-crit CRIT", Integer, "Critical percentage memory used") do |f|
    @options[:memory_percent_crit] = f
end

opt.on("--mem-warn WARN", Integer, "Warning percentage memory used") do |f|
    @options[:memory_percent_warn] = f
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

output = ["ActiveMQ"]
statuses = [0]
perfdata = []

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

        conn.publish("/queue/ActiveMQ.Statistics.Destination.#{@options[:queue]}", "", {"reply-to" => "/topic/nagios.statresults.#{hostname}"})

        s = conn.receive.body
        conn.disconnect

        map = amqxmldecode(s)


        perfdata << "size=#{map[:size]}"
        perfdata << "memory_pct=#{map[:memoryPercentUsage]}"

        if map[:size] >= @options[:queue_crit]
            output << "CRIT: #{@options[:queue]} has #{map[:size]} messages"
            statuses << 2
        elsif map[:size] >= @options[:queue_warn]
            output << "WARN: #{@options[:queue]} has #{map[:size]} messages"
            statuses << 1
        else
            output << "#{@options[:queue]} has #{map[:size]} messages"
            statuses << 0
        end

        if map[:memoryPercentUsage] >= @options[:memory_percent_crit]
            output << "CRIT: #{map[:memoryPercentUsage]} % memory used"
            statuses << 2
        elsif map[:memoryPercentUsage] >= @options[:memory_percent_warn]
            output << "WARN: #{map[:memoryPercentUsage]} % memory used"
            statuses << 1
        else
            output << "#{map[:memoryPercentUsage]} % memory used"
            statuses << 0
        end
    end
rescue Exception => e
    output = ["UNKNOWN: Failed to get ActiveMQ stats: #{e}"]
    statuses = [3]
end

puts "%s|%s" % [output.join(" "), perfdata.join(" ")]

exit(statuses.max)
