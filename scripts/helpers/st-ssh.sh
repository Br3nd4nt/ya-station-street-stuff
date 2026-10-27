#!/bin/sh
# Run a command on the station, waiting for it to come back first.
# Usage: st-ssh.sh 'command'
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOST=${ST_HOST:-192.168.10.185}
PORT=${ST_PORT:-2222}
"$HERE/st-wait.sh" || exit 1
exec ssh -p "$PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$HOST" "$@"
