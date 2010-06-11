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
# == Usage
# diskstatsparse.rb --device DEVICE
#
# --device DEVICE
# The device to retrieve stats for, example "sda"
#
# --help
# Shows this help page
#
# == Author
# R.I.Pienaar <rip@devco.net>

require 'getoptlong'

opts = GetoptLong.new(
	[ '--device', '-d', GetoptLong::REQUIRED_ARGUMENT],
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

opts.each do |opt, arg|
	case opt
	when '--help'
		showhelp
		exit
	when '--device'
		device = arg
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
		puts(line[0].split)
	else
		raise("Could not find stats for device #{device}")
	end
rescue Exception => e
	puts("Failed to parse /proc/diskstats: #{e}")
	exit(2)
end
