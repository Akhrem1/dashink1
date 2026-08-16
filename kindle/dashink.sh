#!/bin/sh
# dashink display loop for a jailbroken Kindle (KT2, firmware 5.12.2.2).
#
# Install to /mnt/us/documents/. The KindleModding Hotfix's sh_integration makes
# .sh files there appear in the library as tappable entries, so this needs no
# launcher. KUAL is still used on the device for GTK extensions such as kterm,
# but nothing here depends on it.
#
# WARNING: this stops the reader UI. Once lab126_gui is stopped the touchscreen
# does nothing, which includes the library entry for restore.sh. The only way
# back is `start lab126_gui` over SSH, or holding power ~20s. Have SSH working
# before you run this.

set -u

# `stop` is an upstart symlink in /sbin, which is on the framework's PATH but
# not on the one ssh gives you. Set it explicitly so this works from either.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

URL="${DASHINK_URL:-http://dashink.lan:8099/dash.png}"
INTERVAL="${DASHINK_INTERVAL:-300}"
OUT=/tmp/dashink.png

# Full refresh every Nth cycle to clear e-ink ghosting. 12 x 300s = hourly.
FULL_EVERY=12

# Silent on failure. sh_integration draws anything a script writes to stdout
# straight onto the panel, so -S would paint curl's error over the dashboard.
# Failures go to the log instead.
fetch() {
  if command -v curl > /dev/null 2>&1; then
    curl -fs -m 20 -o "$1" "$URL" 2> /dev/null
  else
    wget -q -T 20 -O "$1" "$URL" 2> /dev/null
  fi
}

# Refuse to start twice. The launcher is a library entry, so a double-tap is
# easy, and two loops both calling eips -g on the same file fight over the panel
# with no visible cause. A PID file rather than matching on ps output: busybox
# carries neither pgrep nor flock reliably here, and sh_integration may wrap the
# script in a way that makes it appear twice in ps.
LOCK=/tmp/dashink.pid
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2> /dev/null)" 2> /dev/null; then
  exit 0
fi
echo $$ > "$LOCK"

stop lab126_gui > /dev/null 2>&1
lipc-set-prop com.lab126.powerd preventScreenSaver 1 > /dev/null 2>&1

# Silenced for the same reason: eips prints "update_to_display: update_mode=...
# wave_mode=..." on every call, straight onto the dashboard.
eips -c > /dev/null 2>&1
i=0
fails=0

while true; do
  if fetch "$OUT.tmp" && [ -s "$OUT.tmp" ]; then
    mv "$OUT.tmp" "$OUT"
    fails=0
    i=$((i + 1))
    [ $((i % FULL_EVERY)) -eq 0 ] && eips -c > /dev/null 2>&1
    eips -g "$OUT" > /dev/null 2>&1
    # Re-asserted every cycle. powerd resets it on some firmware events, and a
    # screensaver that comes back blanks the panel with nothing to bring it
    # back. One lipc call every five minutes removes that whole failure mode.
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 > /dev/null 2>&1
    sleep "$INTERVAL"
  else
    rm -f "$OUT.tmp"
    # Leave the last good frame up and log rather than drawing over it. The
    # rendered image carries its own "updated HH:MM", so a frame whose
    # clock has stopped already says the fetch died. No overlay needed, and no
    # hardcoded row that breaks when the panel is not the size it assumed.
    fails=$((fails + 1))
    echo "$(date '+%Y-%m-%d %H:%M:%S') fetch failed ($fails)" >> /tmp/dashink.log

    # Kindles do not always rejoin a network after a long outage. Without this
    # the loop retries into a dead interface until someone notices the panel
    # froze overnight. Fired once at a threshold rather than every cycle, so it
    # does not thrash the radio.
    [ "$fails" -eq 6 ] && lipc-set-prop com.lab126.cmd wirelessEnable 1 > /dev/null 2>&1

    # Back off after a few misses. Where the network is down for hours at a
    # time, a plain retry loop wakes the radio every INTERVAL for nothing.
    # Capped at 2x so the panel still recovers within ten minutes of the network
    # returning.
    if [ "$fails" -ge 3 ]; then
      sleep $((INTERVAL * 2))
    else
      sleep "$INTERVAL"
    fi
  fi
done
