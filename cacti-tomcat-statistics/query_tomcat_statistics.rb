#!/usr/bin/ruby

# Simple script to fetch memory and connector stats from tomcat manager

require 'net/http'
require 'rexml/document'
require 'optparse'
require 'uri'
require 'pp'

@options = {:user => nil,
            :password => nil,
            :url => "http://localhost/manager/status/",
            :connector => "http-8080"}

opt = OptionParser.new

opt.on("--user [USER]", "-u", "Connect as user") do |val|
    @options[:user] = val
end

opt.on("--password [PASSWORD]", "-p", "Passwod to connect with") do |val|
    @options[:password] = val
end

opt.on("--url [URL]", "-U", "Tomcat manager stats url") do |val|
    @options[:url] = val
end

opt.on("--connector [CONNECTOR]", "Connector to monitor") do |val|
    @options[:connector] = val
end

opt.parse!

def get_url(address, user=nil, password=nil)
    url = URI.parse(address)
    req = Net::HTTP::Get.new(url.path + "?XML=true")
    req.basic_auth user, password if user && password

    res = Net::HTTP.start(url.host, url.port) {|http|
        http.request(req)
    }
    return res.body
end

xml_data = get_url(@options[:url], @options[:user], @options[:password])

doc = REXML::Document.new(xml_data)

output = []

doc.root.elements["jvm"].elements["memory"].attributes.each_pair do |attribute, value|
    output << "memory_#{attribute}:#{value}"
end

doc.root.elements["connector[@name='#{@options[:connector]}']"].elements["threadInfo"].attributes.each_pair do |attribute, value|
    output << "#{attribute}:#{value}"
end

puts output.join(" ")
