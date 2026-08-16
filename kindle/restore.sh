#!/bin/sh
# Stop the dashboard loop and bring the reader UI back.
#
# The escape hatch for dashink.sh, which stops lab126_gui and leaves the
# touchscreen dead — including this file's own library entry. Assume SSH is the
# only way in, and hold power ~20s if it is not.
#
# ps/grep/awk rather than pkill: busybox on 5.12.2.2 may not carry pkill, and
# this is the recovery path.

set -u

# `start` is in /sbin, which is on the framework's PATH but not on ssh's. The
# call below silences stderr, so without this it failed invisibly.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

for pid in $(ps | grep '[d]ashink\.sh' | awk '{print $1}'); do
  kill "$pid" 2> /dev/null
done

rm -f /tmp/dashink.pid

lipc-set-prop com.lab126.powerd preventScreenSaver 0 > /dev/null 2>&1
eips -c > /dev/null 2>&1
start lab126_gui > /dev/null 2>&1
