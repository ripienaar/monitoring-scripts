#!/usr/bin/ruby
# == Synopsis
# Simple nagios plugin to count files in a directory and optionally
# match names to a regex
#
# == Usage
# check_dir --dir DIRNAME --warn WARN --crit CRIT [--regex REGEX]
#
# --dir DIRNAME
#   The directory to check
#
# --warn WARN
#   Number of files to raise a warning for
#
# --crit CRIT
#   Number of files to raise a critical for
#
# --regex REGEX
#   Regular expression to match found files again
#
# --help
#   Show this help
#
# == Author
# R.I.Pienaar <rip@devco.net>


require 'getoptlong'
require 'find'

opts = GetoptLong.new(
	[ '--directory', '-d', GetoptLong::REQUIRED_ARGUMENT],
	[ '--pattern', '-p', GetoptLong::REQUIRED_ARGUMENT],
	[ '--regex', '-r', GetoptLong::REQUIRED_ARGUMENT],
	[ '--warn', '-w', GetoptLong::REQUIRED_ARGUMENT],
	[ '--crit', '-c', GetoptLong::REQUIRED_ARGUMENT],
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

dirname = ""
regex = ""
warn = ""
crit = ""

opts.each { |opt, arg|
	case opt
	when '--help'
		showhelp
		exit
	when '--directory'
		dirname = arg
	when '--regex'
		regex = arg
	when '--warn'
		warn = arg.to_i
	when '--crit'
		crit = arg.to_i
	end
}

if dirname == "" || warn == "" || crit == ""
	showhelp
	exit
end

if warn > crit
	puts("UNKNOWN: Parameters does not make sense, warn >= crit")
	exit(3)
end

fcount = 0

if FileTest.directory?(dirname)
	Dir.entries(dirname).each do |path|
		next if path =~ /^(\.|\.\.)$/

		if regex == ""
			fcount = fcount + 1
		else
			if File.basename(path) =~ /#{regex}/
				fcount = fcount + 1
			end
		end
	end
else
	puts("UNKNOWN: #{dirname} does not exist or is not a directory")
	exit(3)
end

if fcount >= crit
	puts("CRITICAL: #{fcount} files found in #{dirname} expected <= #{crit}")
	exit(2)
elsif fcount >= warn
	puts("WARNING: #{fcount} files found in #{dirname} expected <= #{warn}")
	exit(1)
else
	puts("OK: #{fcount} files found in #{dirname}")
	exit(0)
end
