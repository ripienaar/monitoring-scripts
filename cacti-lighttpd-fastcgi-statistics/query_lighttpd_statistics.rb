#!/usr/bin/ruby

# Where on the lighttpd server to find the server statistics
COUNTER_PATH="/server-counters"

require 'net/http'
require 'optparse'
require 'pp'

# Gets the stat file and prints out the unique CGIs found in it
def index(host)
    backends = {}

    get(host) do |stat|
        backends[stat[:backend]] = 1
    end

    puts backends.keys.sort.join("\n")
end

# Returns a specific stat for all CGI or just one if backend is given
def query(host, field, backend=nil)
    if backend.nil?
        parse(host).each_pair do |backend, stats|
            puts "#{backend}:#{stats[field]}"
        end
    else
        puts parse(host)[backend][field]
    end
end

# Retrieves the stat and builds a hash of hashes representing it
def parse(host)
    backends = {}

    new_backend = {:cgi => "", :connected => 0, :died => 0, :disabled => 0,
                   :load => 0, :overloaded => 0, :processes => 0} 

    get(host) do |stat|
        backend = stat[:backend]

        unless backends.include?(backend)
            backends[backend] = new_backend.clone
            backends[backend][:cgi] = backend
        end

        backends[backend][stat[:stat]] = backends[backend].fetch(stat[:stat], 0) + stat[:value]
    end

    backends
end

# Parses a backend line returning a hash of its bits
def parse_line(line)
    ret = {}

    if line =~ /^fastcgi\.backend\.(.+)\.(\d+)\.(connected|died|disabled|load|overloaded): (\d+)$/
        ret[:backend] = $1
        ret[:instance_number] = $2.to_i
        ret[:stat] = $3.to_sym
        ret[:value] = $4.to_i
    else
        raise "Unparsable line: #{line}"
    end

    ret
end

# Retrieves a url from a remote host
def get(host)
    url = "http://#{host}#{COUNTER_PATH}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)

    response = http.get(uri.path)

    unless response.code == "200"
        puts "Failed to retrieve #{url}: #{response.code}"
        exit 1
    end

    unless block_given?
        response.body.split(/\n/)
    else
        response.body.split(/\n/).each do |line|
            begin
                yield(parse_line(line))
            rescue Exception => e
            end
        end
    end
end

host = nil
command = nil
field = nil
backend = nil

if ARGV.size > 1
    host = ARGV[0]
    command = ARGV[1].to_sym

    field = ARGV[2].to_sym if ARGV.size > 2
    backend = ARGV[3] if ARGV.size > 3
end

unless host && command
    puts "Please specify a host and command"
    exit 1
end

case command
    when :index
        index(host)

    when :query
        query(host, field)

    when :get
        query(host, field, backend)

    else
        puts "Unknown command: #{command}"
        exit 1
end
