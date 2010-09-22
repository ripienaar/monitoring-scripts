#!/usr/bin/ruby

# Parses the Lighttpd server status BusyServers value and reports critical 
# or warning
#
# To set up lighttpd for this, add something like:
#
#   $HTTP["remoteip"] =~ "^(10|127)" {
#        status.status-url = "/server-status"
#   }
# 
# R.I.Pienaar <rip@devco.net> Apache version 2 license

require 'net/http'
require 'optparse'
require 'yaml'
require 'pp'

critical = warn = 0
host = "localhost"
statsurl = "/server-status"

opt = OptionParser.new

opt.on("--critical [CRIT]", "-c", Integer, "Critical load") do |f|
    critical = f.to_i
end

opt.on("--warn [WARN]", "-w", Integer, "Warning load") do |f|
    warn = f.to_i
end

opt.on("--url [URL]", "-u", "Status URL") do |f|
    statsurl = f
end

opt.on("--host [HOST]", "-h", "Host to check") do |f|
    host = f
end

opt.parse!

# Retrieves a url from a remote host
def get(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)

    response = http.get("#{uri.path}?auto")

    unless response.code == "200"
        puts "Failed to retrieve #{url}: #{response.code}"
        exit 3
    end

    response.body
end

stats = YAML.load(get("http://#{host}/#{statsurl}"))

if stats.include?("BusyServers")
    if stats["BusyServers"] >= critical
        puts "CRITICAL: #{stats['BusyServers']} >= #{critical} lighttpd busy servers"
        exit 2
    elsif stats["BusyServers"] >= warn
        puts "WARNING: #{stats['BusyServers']} >= #{warn} lighttpd busy servers"
        exit 1
    else
        puts "OK: #{stats['BusyServers']} lighttpd busy servers"
        exit 0
    end
else
    puts "Could not parse lighttpd statistics"
    exit 3
end
