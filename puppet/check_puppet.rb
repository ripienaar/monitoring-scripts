#!/usr/bin/ruby

# A simple nagios check that should be run as root
# perhaps under the mcollective NRPE plugin and
# can check when the last run was done of puppet.
# It can also check fail counts and skip machines
# that are not enabled
#
# The script will use the puppet last_run-summar.yaml
# file to determine when last Puppet ran else the age
# of the statefile.

require 'optparse'
require 'yaml'

lockfile = "/var/lib/puppet/state/puppetdlock"
statefile = "/var/lib/puppet/state/state.yaml"
summaryfile = "/var/lib/puppet/state/last_run_summary.yaml"
enabled = true
enabled_message = ""
running = false
lastrun_failed = false
lastrun = 0
failcount = 0
warn = 1
crit = 5
warn_time = 1900
crit_time = 3700
total_failure = false
enabled_only = false

opt = OptionParser.new

opt.on("--critical_time [CRIT]", "-x", Integer, "Critical threshold for time last run") do |f|
    crit_time = f.to_i
end

opt.on("--warn_time [WARN]", "-u", Integer, "Warning thresold for time last run") do |f|
    warn_time = f.to_i
end

opt.on("--critical [CRIT]", "-c", Integer, "Critical threshold, time or failed resources") do |f|
    crit = f.to_i
end

opt.on("--warn [WARN]", "-w", Integer, "Warning thresold, time of failed resources") do |f|
    warn = f.to_i
end

opt.on("--only-enabled", "-e", "Only alert if Puppet is enabled") do |f|
    enabled_only = true
end

opt.on("--lock-file [FILE]", "-l", "Location of the lock file, default #{lockfile}") do |f|
    lockfile = f
end

opt.on("--state-file [FILE]", "-t", "Location of the state file, default #{statefile}") do |f|
    statefile = f
end

opt.on("--summary-file [FILE]", "-s", "Location of the summary file, default #{summaryfile}") do |f|
    summaryfile = f
end

opt.parse!

if File.exists?(lockfile)
    if File::Stat.new(lockfile).zero?
       enabled = false
       enabled_message = "Puppet disabled. "
    else
       running = true
    end
end

lastrun = File.stat(statefile).mtime.to_i if File.exists?(statefile)

if File.exists?(summaryfile)
    begin
        summary = YAML.load_file(summaryfile)
        lastrun = summary["time"]["last_run"]

        # machines that outright failed to run like on missing dependencies
        # are treated as huge failures.  The yaml file will be valid but
        # it wont have anything but last_run in it
        unless summary.include?("events")
            failcount = 99
            total_failure = true
        else
            # and unless there are failures, the events hash just wont have the failure count
            failcount = summary["events"]["failure"] || 0
        end
    rescue
        failcount = 0
        summary = nil
    end
end

time_since_last_run = Time.now.to_i - lastrun

if enabled_only && enabled == false
    puts "OK: #{enabled_message}Not alerting due to -e flag. Last run #{time_since_last_run} seconds ago with #{failcount} failures"
    exit 0
end

if total_failure
    puts "CRITICAL: FAILED - Puppet failed to run. Missing dependencies? Catalog compilation failed? Puppet last ran #{time_since_last_run} seconds ago"
    exit 2
elsif failcount >= crit
    puts "CRITICAL: #{enabled_message}Puppet last ran had #{failcount} failures, expected < #{crit}. Puppet last ran #{time_since_last_run} seconds ago"
    exit 2
elsif failcount >= warn
    puts "WARNING: #{enabled_message}Puppet last ran had #{failcount} failures, expected < #{warn}. Puppet last ran #{time_since_last_run} seconds ago"
    exit 1
elsif time_since_last_run >= crit_time
    puts "CRITICAL: #{enabled_message}Puppet last ran #{time_since_last_run} seconds ago, expected < #{crit_time} seconds"
    exit 2
elsif time_since_last_run >= warn_time
    puts "WARNING: #{enabled_message}Puppet last ran #{time_since_last_run} seconds ago, expected < #{warn_time} seconds"
    exit 1
else
    if enabled
        puts "OK: #{enabled_message}Puppet last ran #{time_since_last_run} seconds ago with #{failcount} failures"
    else
        puts "WARNING: #{enabled_message}Puppet last ran #{time_since_last_run} seconds ago with #{failcount} failures"
        exit 1
    end

    exit 0
end
