#!/bin/sh
# Wait until the station answers on ping + ssh. Handles flaky wifi.
# Usage: st-wait.sh HOST [PORT] [timeout_seconds]
set -u
HOST=${1:-${ST_HOST:-}}
PORT=${2:-${ST_PORT:-2222}}
LIMIT=${3:-300}

if [ -z "$HOST" ]; then
    echo "usage: $0 HOST [PORT] [timeout_seconds]  (or set ST_HOST)" >&2
    exit 2
fi

i=0
while [ "$i" -lt "$LIMIT" ]; do
    if ping -c 1 -W 1000 "$HOST" >/dev/null 2>&1; then
        if ssh -n -p "$PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
               root@"$HOST" true >/dev/null 2>&1; then
            exit 0
        fi
    fi
    i=$((i + 2))
    sleep 2
done
echo "station $HOST:$PORT not reachable after ${LIMIT}s" >&2
exit 1