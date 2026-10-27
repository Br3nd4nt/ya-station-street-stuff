#!/bin/sh
# Run a command on the station, waiting for it to come back first.
# Usage: st-ssh.sh HOST [PORT] 'command'
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOST=${1:-${ST_HOST:-}}
PORT=${2:-${ST_PORT:-2222}}

if [ -z "$HOST" ]; then
    echo "usage: $0 HOST [PORT] 'command'  (or set ST_HOST)" >&2
    exit 2
fi
shift 2 2>/dev/null || shift 1

"$HERE/st-wait.sh" "$HOST" "$PORT" || exit 1
exec ssh -p "$PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$HOST" "$@"