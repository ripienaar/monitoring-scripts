#!/usr/bin/ruby
# == Synopsis
# Simple nagios plugin to check expiry times for certificates
# and CRLs
#
# == Usage
# Check a certificate:
#   check_cert --cert /path/to/cert --warn WARN --crit CRIT
#
# Check a crl:
#   check_cert --crl /path/to/crl --warn WARN --crit CRIT
#
# --warn WARN
#   Seconds before expiry to raise a warning
#
# --crit CRIT
#   Seconds before expiry to raise a critical
#
# --help
#   Show this help
#
# == Author
# R.I.Pienaar <rip@devco.net>


require 'getoptlong'
require 'date'

opts = GetoptLong.new(
        [ '--cert',       GetoptLong::REQUIRED_ARGUMENT],
        [ '--crl',        GetoptLong::REQUIRED_ARGUMENT],
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

cert = ""
crl  = ""
warn = ""
crit = ""

opts.each { |opt, arg|
        case opt
        when '--help'
                showhelp
                exit
        when '--cert'
                cert = arg
        when '--crl'
                crl = arg
        when '--warn'
                warn = arg.to_i
        when '--crit'
                crit = arg.to_i
        end
}

if (cert == "" && crl == "") || warn == "" || crit == ""
        showhelp
        exit
end

if warn < crit
        puts("UNKNOWN: Parameters does not make sense, warn <= crit")
        exit(3)
end

# Takes a period of time in seconds and returns it in human-readable form (down to minutes)
def time_period_to_s(time_period)
  out_str = ''
  interval_array = [ [:years, 31556926], [:weeks, 604800], [:days, 86400], [:hours, 3600], [:mins, 60] ]

  interval_array.each do |sub|
	if time_period>= sub[1] then
	  time_val, time_period = time_period.divmod( sub[1] )
	  name = sub[0].to_s
	  ( sub[0] != :mins ? out_str += ", " : out_str += " and " ) if out_str != ''
	  out_str += time_val.to_s + " #{name}"
	end
  end
  return out_str
end

def alert_age(file, enddate, warn, crit)
    seconds = Date.parse(enddate).strftime('%s').to_i - Time.now.strftime('%s').to_i

    if seconds < crit
        puts("CRITICAL: #{file} expires in #{time_period_to_s(seconds)}")
        exit(2)
    elsif seconds < warn
        puts("WARN: #{file} expires in #{time_period_to_s(seconds)}")
        exit(1)
    else
        puts("OK: #{file} expires in #{time_period_to_s(seconds)}")
        exit(0)
    end
end

def check_cert(cert, warn, crit)
    if File.exists?(cert)
        enddate = %x{openssl x509 -in #{cert} -noout -enddate}

        if enddate =~ /notAfter=(.+)/
            enddate = $1
        else
            puts("UNKNOWN: Certifcate end date could not be parsed")
            exit(3)
        end

        alert_age(cert, enddate, warn, crit)
    else
        puts("UNKNOWN: Certificate #{cert} doesn't exist")
        exit(3)
    end
end

def check_crl(crl, warn, crit)
    if File.exists?(crl)
        enddate = %x{openssl crl -in #{crl} -noout -nextupdate}

        if enddate =~ /nextUpdate=(.+)/
            enddate = $1
        else
            puts("UNKNOWN: CRL next update date could not be parsed")
            exit(3)
        end

        alert_age(crl, enddate, warn, crit)
    else
        puts("UNKNOWN: CRL #{crl} doesn't exist")
        exit(3)
    end
end

if cert != ""
    check_cert(cert, warn, crit)
elsif crl != ""
    check_crl(crl, warn, crit)
else
    puts("UNKNOWN: Don't know what to check, crl and cert is unset")
    exit(3)
end
