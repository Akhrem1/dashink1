#!/bin/sh
# Stop the dashboard loop and bring the reader UI back.
#
# The escape hatch for dashink.sh, which stops lab126_gui and leaves the
# touchscreen dead. That also kills the library, so this file's own entry there
# is unreachable exactly when it is needed. Assume SSH is the only way in, and
# hold power ~20s if it is not available.
#
# ps/grep/awk rather than pkill: busybox on 5.12.2.2 is not guaranteed to carry
# pkill, and this script is the recovery path, so it cannot depend on a maybe.

set -u

# `start` is an upstart symlink in /sbin, which is on the framework's PATH but
# not on the one ssh gives you. The call below silences stderr, so without this
# "sh: start: not found" went unseen and this script looked like it worked while
# never bringing the reader UI back.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

for pid in $(ps | grep '[p]roxink\.sh' | awk '{print $1}'); do
  kill "$pid" 2> /dev/null
done

rm -f /tmp/dashink.pid

lipc-set-prop com.lab126.powerd preventScreenSaver 0 > /dev/null 2>&1
eips -c > /dev/null 2>&1
start lab126_gui > /dev/null 2>&1
