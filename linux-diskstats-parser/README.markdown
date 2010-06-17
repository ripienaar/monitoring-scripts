Synopsis
========
Simple script to parse /proc/diskstats and pull out stats for a certain
partition


Installation
------------
This script is intended to run from SNMP using the exec directive,
sample config:

   exec .1.3.6.1.4.1.xxxxxx.1 sdaStats /usr/local/bin/diskstatsparse.rb --device sda

Replace the xxx above with your registered OID number.

You can also use this from NRPE or something similar to feed data to Cacti that way:

   command[cacti_sdb_stats]=/usr/local/bin/diskstatsparse.rb --device sdb --mode cacti

In this mode it will output a series of named fields in Cacti standard format.

Usage
-----
diskstatsparse.rb --device DEVICE

--device DEVICE The device to retrieve stats for, example "sda"

--mode MODE The output mode to use, snmp or cacti

--help Shows this help page


Author
------
R.I.Pienaar <rip@devco.net>

