#!/usr/bin/ruby

# A simple plugin that publishes a message to a destination
# queue or topic and wait for it to return.  If the reply
# is not received in a specified time alerts are raised
#
# Connection issues also raise alerts.
#
# The password can be supplied on the command line can either
# be a string for the password or a path to a file that has
# the password on the first line.
#
# If you have multiple nagios instances monitoring the same
# infrastructure you should not use queues but topics and
# each nagios instance should use a unique topic.
#
# We could use temp topics but unfortunately these fail in
# certain middleware topologies.
#
# You can specify --host multiple times but port, user, password
# etc should be the same for all the hosts in that case
#
# R.I.Pienaar <rip@devco.net>
# Apache 2.0 License

require 'rubygems'
require 'stomp'
require 'timeout'
require 'optparse'

options = {:user => "nagios",
           :password => nil,
           :host => nil,
           :port => 61613,
           :destination => "/topic/nagios.monitor",
           :warning => 2,
           :critical => 5}

opt = OptionParser.new

opt.on("--user USER", "-u", "User to connect as") do |v|
    options[:user] = v
end

opt.on("--password PASSWORD", "-p", "Password to connect with") do |v|
    if v.start_with?("/") && File.exist?(v)
        options[:password] = File.read(v).split("\n").first.chomp
    else
        options[:password] = v
    end
end

opt.on("--destination DEST", "-d", "The topic of queue to use for monitoring") do |v|
    options[:destination] = v
end

opt.on("--warning WARN", "-w", "Warning threshold for turn around time") do |v|
    options[:warning] = v.to_i
end

opt.on("--critical CRIT", "-c", "Critical threshold for turn around time") do |v|
    options[:critical] = v.to_i
end

opt.on("--host HOST", "-h", "Host to connect to") do |v|
    if options[:host]
        options[:host] << v
    else
        options[:host] = [v]
    end
end

opt.on("--port PORT", "-p", "Port to connect to") do |v|
    options[:port] = v.to_i
end

opt.parse!

if options[:host].nil?
    puts "CRITICAL: No host to monitor supplied"
    exit 2
end

starttime = Time.now

message = nil
status = 3

# dont spew any stuff to stderr
class EventLogger
    def on_miscerr(params=nil); end
    def on_connectfail(params=nil); end
end

begin
    Timeout::timeout(options[:critical]) do
        connection = {:hosts => [], :logger => EventLogger.new}

        options[:host].each do |host|
            connection[:hosts] << {:host => host, :port => options[:port], :login => options[:user], :passcode => options[:password]}
        end

        conn = Stomp::Connection.open(connection)

        conn.subscribe(options[:destination])

        msg = ""
        10.times { msg += rand(100).to_s }

        send_time = Time.now
        conn.publish(options[:destination], msg)

        body = conn.receive.body

        if msg == body
            status = 0
        else
            message = "CRITICAL: sent #{msg} but received #{body} possible corruption of miss configuration"
            status = 2
        end
    end
rescue Timeout::Error
    status = 2
rescue Exception => e
    message = "CRITICAL: Unexpected error during test: #{e}"
    status = 2
end

testtime = (Time.now - starttime).to_f

if testtime >= options[:critical]
    message = "CRITICAL: Test took %.2f to complete expected < %d" % [ testtime, options[:critical] ]
    status = 2
elsif testtime >= options[:warning]
    puts "WARNING: Test took %.2f to complete expected < %d" % [ testtime, options[:warning] ]
    status = 1
end

if status == 0
    if message
        puts "%s|seconds=%f" % [ message, testtime ]
    else
        puts "OK: Test completed in %.2f seconds|seconds=%f" % [ testtime, testtime ]
    end

    exit 0
else
    if message
        puts "%s|seconds=%f" % [ message, testtime ]
    else
        statusses = {0 => "OK", 1 => "WARNING", 2 => "CRITICAL", 3 => "UNKNOWN"}

        puts "%s: Test completed in %.2f seconds|seconds=%f" % [ statusses[status], testtime, testtime ]
    end

    exit status
end
