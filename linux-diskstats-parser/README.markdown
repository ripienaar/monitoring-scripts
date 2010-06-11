Synopsis
========
Simple script to parse /proc/diskstats and pull out stats for a certain
partition


Installation
------------
This script is intended to run from SNMP using the exec directive,
sample config:

exec .1.3.6.1.4.1.xxxxxx.1 sdaStats /usr/local/bin/diskstatsparse.rb
--device sda

Replace the xxx above with your registered OID number.


Usage
-----
diskstatsparse.rb --device DEVICE

--device DEVICE The device to retrieve stats for, example "sda"

--help Shows this help page


Author
------
R.I.Pienaar <rip@devco.net>

