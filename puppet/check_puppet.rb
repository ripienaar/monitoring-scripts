#!/usr/bin/ruby

# A simple nagios check that should be run as root
# perhaps under the mcollective NRPE plugin and
# can check when the last run was done of puppet.
# It can also check fail counts and skip machines
# that are not enabled
#
# The script will use the puppet last_run_summary.yaml
# file to determine when last Puppet ran else the age
# of the statefile.
#
# 19/12/2013 --- Change to lock files and handling of a puppet agent in a disabled state (WARNING)
#            *** These changes are made to work with puppet 3.X and MAY cause some issues with 2.x users
#            *** The script should still continue to work for 2.x, but may not handle the lockfiles correctly
#            *** and will require the proper arguments to match 2.x filename.
require 'optparse'
require 'yaml'

statedir = "/var/lib/puppet/state"
agent_lockfile = statedir + "/agent_catalog_run.lock"
agent_disabled_lockfile = statedir + "/agent_disabled.lock"
statefile = statedir + "/state.yaml"
summaryfile = statedir + "/last_run_summary.yaml"
enabled = true
running = false
lastrun_failed = false
lastrun = 0
failcount_resources = 0
failcount_events = 0
warn = 0
crit = 0
total_failure = false
enabled_only = false
failures = false
disable_perfdata = false

opt = OptionParser.new

opt.on("--critical [CRIT]", "-c", Integer, "Critical threshold, time or failed resources") do |f|
    crit = f.to_i
end

opt.on("--warn [WARN]", "-w", Integer, "Warning threshold, time or failed resources") do |f|
    warn = f.to_i
end

opt.on("--check-failures", "-f", "Check for failed resources instead of time since run") do |f|
    failures = true
end

opt.on("--only-enabled", "-e", "Only alert if Puppet is enabled") do |f|
    enabled_only = true
end

opt.on("--state-dir [FILE]", "Location of the state directory containing lock and state files, default #{statedir}, will change location of the files") do |f|
    statedir = f
    agent_lockfile = statedir + "/agent_catalog_run.lock"
    agent_disabled_lockfile = statedir + "/agent_disabled.lock"
    statefile = statedir + "/state.yaml"
    summaryfile = statedir + "/last_run_summary.yaml"
end

opt.on("--agent-lock-file [FILE]", "-l", "Location of the agent run lock file, default #{agent_lockfile}") do |f|
    agent_lockfile = f
end

opt.on("--agent-disabled-lock-file [FILE]", "-d", "Location of the agent disabled lock file, default #{agent_disabled_lockfile}") do |f|
    agent_disabled_lockfile = f
end

opt.on("--state-file [FILE]", "-t", "Location of the state file, default #{statefile}") do |f|
    statefile = f
end

opt.on("--summary-file [FILE]", "-s", "Location of the summary file, default #{summaryfile}") do |f|
    summaryfile = f
end

opt.on("--disable-perfdata", "-x", "Disable performance data output") do |f|
    disable_perfdata = f
end

opt.parse!

if warn == 0 || crit == 0
    puts "Please specify a warning and critical level"
    exit 3
end

if File.exists?(agent_lockfile)
    if File::Stat.new(agent_lockfile).zero?
       enabled = false
    else
       running = true
    end
end

if File.exists?(agent_disabled_lockfile)
    enabled = false
end


lastrun = File.stat(statefile).mtime.to_i if File.exists?(statefile)

unless File.readable?(summaryfile)
    puts "UNKNOWN: Summary file not found or not readable. Check #{summaryfile}"
    exit 3
else
    begin
        summary = YAML.load_file(summaryfile)
        lastrun = summary["time"]["last_run"]

        # machines that outright failed to run like on missing dependencies
        # are treated as huge failures.  The yaml file will be valid but
        # it wont have anything but last_run in it
        unless summary.include?("events")
            failcount_resources = 99
            failcount_events = 99
            total_failure = true
        else
            # and unless there are failures, the events hash just wont have the failure count
            failcount_resources = summary["resources"]["failed"] || 0
            failcount_events = summary["events"]["failure"] || 0
        end
    rescue
        failcount_resources = 0
        failcount_events = 0
        summary = nil
    end
end

time_since_last_run = Time.now.to_i - lastrun

time_since_last_run_string = "#{time_since_last_run} seconds ago"
if time_since_last_run >= 3600
  time_since_last_run_string = "#{time_since_last_run / 60 / 60} hours ago at #{Time.at(Time.now - time_since_last_run).utc.strftime('%R:%S')} UTC"
elsif time_since_last_run >= 60
  time_since_last_run_string = "#{time_since_last_run / 60} minutes ago"
end

if disable_perfdata
  perfdata_time = ""
else
  perfdata_time = "|time_since_last_run=#{time_since_last_run}s;#{warn};#{crit};0 failed_resources=#{failcount_resources};;;0 failed_events=#{failcount_events};;;0"
end

unless failures
    if enabled_only && enabled == false
        puts "OK: Puppet is currently disabled, not alerting. Last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events#{perfdata_time}"
        exit 0
    end

    if total_failure
        puts "CRITICAL: FAILED - Puppet failed to run. Missing dependencies? Catalog compilation failed? Last run #{time_since_last_run_string}#{perfdata_time}"
        exit 2
    elsif time_since_last_run >= crit
        puts "CRITICAL: last run #{time_since_last_run_string}, expected < #{crit}s#{perfdata_time}"
        exit 2

    elsif time_since_last_run >= warn
        puts "WARNING: last run #{time_since_last_run_string}, expected < #{warn}s#{perfdata_time}"
        exit 1

    else
        if enabled
            puts "OK: last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events and currently enabled#{perfdata_time}"
        else
            puts "WARNING: last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events and currently disabled#{perfdata_time}"
            exit 1
         end

        exit 0
    end
else
    if enabled_only && enabled == false
        puts "OK: Puppet is currently disabled, not alerting. Last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events#{perfdata_time}"
        exit 0
    end

    if total_failure
        puts "CRITICAL: FAILED - Puppet failed to run. Missing dependencies? Catalog compilation failed? Last run #{time_since_last_run_string}#{perfdata_time}"
        exit 2
    elsif failcount_resources >= crit
        puts "CRITICAL: Puppet last ran had #{failcount_resources} failed resources #{failcount_events} failed events, expected < #{crit}#{perfdata_time}"
        exit 2

    elsif failcount_resources >= warn
        puts "WARNING: Puppet last ran had #{failcount_resources} failed resources #{failcount_events} failed events, expected < #{warn}#{perfdata_time}"
        exit 1

    else
        if enabled
            puts "OK: last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events and currently enabled#{perfdata_time}"
        else
            puts "WARNING: last run #{time_since_last_run_string} with #{failcount_resources} failed resources #{failcount_events} failed events and currently disabled#{perfdata_time}"
            exit 1
        end

        exit 0
    end
end
