#!/bin/bash
# Push storage pool usage and disk health to dashink, from cron every 15 minutes.
#
# Runs on the machine that can see the pool, which is not necessarily the one
# running dashink, hence a push rather than the dashboard pulling. df/statfs
# reads the cached in-memory superblock and does not spin up a parked disk. Keep
# it that way: do not add du, find, or anything that walks the tree, or the
# array never idles.
#
# Config lives in /etc/dashink.env, kept out of git because of the token:
#   DASHINK_URL=http://<dashink-host>:8099/ingest/media
#   DASHINK_TOKEN=<same value as INGEST_TOKEN in the dashink .env>
#   DASHINK_MOUNT=/mnt/media   # optional, this is the default
#
# SMART is optional and only appears if snapraid writes /var/log/snapraid-smart-*.log.

set -euo pipefail

[ -r /etc/dashink.env ] && . /etc/dashink.env

MOUNT="${DASHINK_MOUNT:-/mnt/media}"
URL="${DASHINK_URL:?DASHINK_URL not set (see /etc/dashink.env)}"
TOKEN="${DASHINK_TOKEN:?DASHINK_TOKEN not set (see /etc/dashink.env)}"

if ! mountpoint -q "$MOUNT"; then
  echo "$MOUNT is not a mountpoint: refusing to report root filesystem usage" >&2
  exit 1
fi

read -r total used avail < <(df -B1 --output=size,used,avail "$MOUNT" | tail -n1)

# SMART comes from the newest snapraid-smart log, not from smartctl. The weekly
# cron already collected it, and re-reading a log on the system disk cannot wake
# a parked data disk. Polling smartctl here every 15 minutes would undo hd-idle.
#
# Fail-soft by design: a missing or unparseable log omits the field and the
# dashboard falls back to showing uptime. It must never take the pool figures
# down with it, which is why nothing here is allowed to fail the script.
smart_json=""
smart_log=$(ls -1t /var/log/snapraid-smart-*.log 2>/dev/null | head -1 || true)
if [ -n "$smart_log" ] && [ -r "$smart_log" ]; then
  # Data rows look like:
  #     30    499       0  11% 16.0  ZL2NQ8F2         /dev/sde      d4
  # $3 error count, $4 failure probability, $7 device. Keying on $7 skips the
  # two header lines, the rule, and snapraid's trailing prose.
  smart_fields=$(awk '
    $7 ~ /^\/dev\// {
      n++
      gsub(/%/, "", $4)
      if ($3 + 0 > 0) { bad++; if ($3 + 0 > we) { we = $3 + 0; w = $7 } }
      if ($4 + 0 > fp) fp = $4 + 0
    }
    END { if (n) printf "%d %d %d %d %s\n", n, bad + 0, we + 0, fp + 0, (w == "" ? "-" : w) }
  ' "$smart_log" || true)

  if [ -n "$smart_fields" ]; then
    read -r n bad worst_errors fp worst <<< "$smart_fields"
    smart_json=",\"smart\":{\"disks\":$n,\"bad\":$bad,\"errors\":$worst_errors,\"fp\":$fp,\"worst\":\"$worst\"}"
  fi
fi

curl -fsS -m 10 -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H "X-Dashink-Token: $TOKEN" \
  -d "{\"mount\":\"$MOUNT\",\"total\":$total,\"used\":$used,\"avail\":$avail$smart_json}" \
  > /dev/null

echo "$(date '+%Y-%m-%d %H:%M:%S') pushed $MOUNT: $used/$total bytes used${smart_json:+, SMART from $(basename "$smart_log")}"
