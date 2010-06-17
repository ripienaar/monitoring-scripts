#!/usr/bin/ruby
# == Synopsis
# Simple script to parse /proc/diskstats and pull out stats for a certain partition
# 
# == Installation
# This script is intended to run from SNMP using the exec directive, sample config:
#
# exec .1.3.6.1.4.1.xxxxxx.1 sdaStats /usr/local/bin/diskstatsparse.rb --device sda
#
# Replace the xxx above with your registered OID number.
#
# You can also use this from NRPE or something similar to feed data to Cacti that way:
# 
# command[cacti_sdb_stats]=/usr/local/bin/diskstatsparse.rb --device sdb --mode cacti
#
# In this mode it will output a series of named fields in Cacti standard format.
#
# == Usage
# diskstatsparse.rb --device DEVICE
#
# --device DEVICE
# The device to retrieve stats for, example "sda"
#
# --mode MODE
# The mode to operate in, either snmp or cacti.  snmp is default
#
# --help
# Shows this help page
#
# == Author
# R.I.Pienaar <rip@devco.net>

require 'getoptlong'

opts = GetoptLong.new(
	[ '--device', '-d', GetoptLong::REQUIRED_ARGUMENT],
	[ '--mode', '-m', GetoptLong::REQUIRED_ARGUMENT],
	[ '--help', '-h', GetoptLong::NO_ARGUMENT]
)

def showhelp
	begin
		require 'rdoc/ri/ri_paths'
		require 'rdoc/usage'
		RDoc::usage
	rescue LoadError => e
		puts("Install RDoc::usage or view the comments in the top of the script to get detailed help.")
	end
end

device = ""
mode = "snmp"

opts.each do |opt, arg|
	case opt
	when '--help'
		showhelp
		exit
	when '--device'
		device = arg
    when '--mode'
        mode = arg
	end
end

if device == ""
	showhelp
	exit
end

begin
	line = File.open("/proc/diskstats", 'r').select do |l|
		l =~ /\s#{device}\s/
	end

	if (line.size > 0)
        if mode == "snmp"
		    puts(line[0].split)
        elsif mode == "cacti"
            stats = ["reads", "merged_reads", "sectors_read", "read_time", "writes", "writes_merged", "sectors_written", "write_time", "io_in_progress", "io_time", "weighted_io_time"]
            result = []

            line[0].split[3,13].each_with_index do |item, idx|
                result << "#{stats[idx]}:#{item}"
            end

            puts result.join(" ")
        else
            puts "Unknown mode #{mode} should be 'snmp' or 'cacti'"
        end
	else
		raise("Could not find stats for device #{device}")
	end
rescue Exception => e
	puts("Failed to parse /proc/diskstats: #{e}")
	exit(2)
end
