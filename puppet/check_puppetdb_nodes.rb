#!/usr/bin/ruby

# script that connects to puppetdb and check for last-seen ages or node counts

require 'rubygems'
require 'time'
require 'pp'
require 'optparse'

class PuppetDB
  require 'puppet'
  require 'puppet/util/puppetdb'
  require 'puppet/util/run_mode'
  require 'puppet/network/http_pool'
  require 'json'
  require 'uri'

  attr_reader :server, :port

  def initialize(mode = :master, server=nil, port=nil, ssl=true)
    configure(mode)

    @server = server || Puppet::Util::Puppetdb.server
    @port = port || Puppet::Util::Puppetdb.port
    @ssl = ssl

    reset!
  end

  def configure(mode = :master)
    if Puppet.settings.app_defaults_initialized?
       unless mode == Puppet.run_mode.name
         raise "Puppet is already configured for %s mode, can't reconfigure for %s mode" % [Puppet.run_mode.name, mode]
       end

       return
    end

    Puppet.settings.preferred_run_mode = mode
    Puppet.settings.initialize_global_settings
    Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
  end

  def connection
    @connection ||= Puppet::Network::HttpPool.http_instance(@server, @port, @ssl)
  end

  def query(query)
    headers = { "Accept" => "application/json" }
    resp = connection.get(query, headers)
    JSON.parse(resp.body)
  end

  def active_nodes
    nodes.reject{|n| n["deactivated"]}
  end

  def deactivated_nodes
    nodes.select{|n| n["deactivated"]}
  end

  def nodes
    @nodes ||= query("/v3/nodes")
  end

  def reset!
    @nodes = nil
    @connection = nil
  end

  def to_s
    "PuppetDB at %s:%s" % [@server, @port]
  end
end

class NodeChecker
  NAGIOS_OK = 0
  NAGIOS_WARN = 1
  NAGIOS_CRIT = 2
  NAGIOS_UNKNOWN = 3

  def initialize(puppetdb, config)
     @puppetdb = puppetdb
     @config = config

     validate!
  end

  def validate!
    raise("Please specify a critical threshold") unless @config[:critical]
    raise("Please specify a warning threshold") unless @config[:warning]
  end

  def report_and_exit(check)
    puts "%s | %s" % [check[:message], check[:stats].map{|k,v| "%s=%.2f" % [k,v]}.join(", ")]
    exit check[:status]
  end

  def nodes
    @nodes ||= @puppetdb.active_nodes.sort_by{|n| Time.parse(n["catalog_timestamp"])}.reverse
  end

  def older_than(seconds)
    nodes.select do |node|
      seconds <= (Time.now - Time.parse(node["catalog_timestamp"])).to_i
    end
  end

  def newest
    nodes.first
  end

  def oldest
    nodes.last
  end

  def newest_age
    Time.now - Time.parse(newest["catalog_timestamp"])
  end

  def oldest_age
    Time.now - Time.parse(oldest["catalog_timestamp"])
  end

  def stats
    {:oldest => oldest_age,
     :newest => newest_age,
     :count => nodes.size}
  end
end

class NodeCountChecker < NodeChecker
  def check
    @puppetdb.reset!

    if @config[:critical] >= @config[:warning]
      if nodes.size >= @config[:critical]
        {:status => NAGIOS_CRIT,
         :message => "CRITICAL: %d nodes in population but expected < %d" % [nodes.size, @config[:critical]],
         :stats => stats}
      elsif nodes.size > @config[:warning]
        {:status => NAGIOS_WARN,
         :message => "WARNING: %d nodes in population but expected < %d" % [nodes.size, @config[:warning]],
         :stats => stats}
      else
        {:status => NAGIOS_OK,
         :message => "OK: %d nodes in population" % nodes.size,
         :stats => stats}
      end
    else
      if nodes.size <= @config[:critical]
        {:status => NAGIOS_CRIT,
         :message => "CRITICAL: %d nodes in population but expected > %d" % [nodes.size, @config[:critical]],
         :stats => stats}
      elsif nodes.size < @config[:warning]
        {:status => NAGIOS_WARN,
         :message => "WARNING: %d nodes in population but expected > %d" % [nodes.size, @config[:warning]],
         :stats => stats}
      else
        {:status => NAGIOS_OK,
         :message => "OK: %d nodes in population" % nodes.size,
         :stats => stats}
      end
    end
  end
end

class AgeChecker < NodeChecker
  def validate!
    super
    raise("Critical threshold is smaller than warning threshold") if @config[:critical] < @config[:warning]
  end

  def check
    @puppetdb.reset!

    return({:status => NAGIOS_UNKNOWN, :message => "Could not find any nodes", :stats => stats}) if nodes.empty?

    if oldest_age >= @config[:critical]
      {:status => NAGIOS_CRIT,
       :message => "CRITICAL: %d nodes not seen in %d seconds" % [older_than(@config[:critical]).size, @config[:critical]],
       :stats => stats}

    elsif oldest_age >= @config[:warning]
      {:status => NAGIOS_WARN,
       :message => "WARNING: %d nodes not seen in %d seconds" % [older_than(@config[:warning]).size, @config[:warning]],
       :stats => stats}

    else
      {:status => NAGIOS_OK,
       :message => "OK: %d nodes checking in sooner than %d seconds" % [nodes.size, @config[:warning]],
       :stats => stats}
    end
  end
end

@config = {:mode => nil, :critical => nil, :warning => nil, :port => nil, :host => nil, :ssl => true}

opt = OptionParser.new

opt.on("--check-age", "--age", "Checks for nodes that have not checked in") do
  @config[:mode] = :age
end

opt.on("--check-nodes", "--nodes", "Checks for the amount of active nodes") do
  @config[:mode] = :node_count
end

opt.on("--critical THRESHOLD", Integer, "Critical threshold") do |v|
  @config[:critical] = v
end

opt.on("--warning THRESHOLD", Integer, "Warning threshold") do |v|
  @config[:warning] = v
end

opt.on("--host HOST", "Hostname where PuppetDB runs") do |v|
  @config[:host] = v
end

opt.on("--port PORT", Integer, "Port where PuppetDB runs") do |v|
  @config[:port] = v
end

opt.on("--[no-]ssl", "Use SSL to connect to PuppetDB") do |v|
  @config[:ssl] = v
end

opt.parse!

puppetdb = PuppetDB.new(:master, @config[:host], @config[:port], @config[:ssl])

case @config[:mode]
  when :age
    checker = AgeChecker.new(puppetdb, @config)

  when :node_count
    checker = NodeCountChecker.new(puppetdb, @config)

  else
    abort("A mode like --check-age is needed")
end

checker.report_and_exit(checker.check)
