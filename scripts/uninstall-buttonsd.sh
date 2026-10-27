#!/bin/sh
# uninstall-buttonsd.sh - stop and remove buttonsd, restore normal mode.
#
# Order matters: remove buttonsd init scripts first, then disable bunker
# mode so maind/platformd can start again on next boot.
#
# Usage: uninstall-buttonsd.sh HOST [PORT] [--reboot]
#   HOST may be omitted only if $ST_HOST is set.
#   PORT defaults to 2222 (override with $ST_PORT).
#   --reboot  reboot the station at the end so normal mode takes effect.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

HOST=""
PORT=2222
DO_REBOOT=0

for arg in "$@"; do
    case "$arg" in
        --reboot) DO_REBOOT=1 ;;
        *)        if [ -z "$HOST" ]; then HOST=$arg; else PORT=$arg; fi ;;
    esac
done
HOST=${HOST:-${ST_HOST:-}}
PORT=${PORT:-${ST_PORT:-2222}}

if [ -z "$HOST" ]; then
    echo "usage: $0 HOST [PORT] [--reboot]  (or set ST_HOST)" >&2
    exit 2
fi

SSH="ssh -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$HOST"

"$HERE/helpers/st-wait.sh" "$HOST" "$PORT" 300 || exit 1

echo "[1/3] stop and remove buttonsd init scripts"
$SSH '
    /etc/init.d/S98buttonsd stop 2>/dev/null
    mount -o remount,rw / || exit 1
    rm -f /etc/init.d/S98buttonsd /etc/init.d/S50ledoff /etc/init.d/S05ledoff
    sync
    mount -o remount,ro /
    echo "init scripts removed"
'

echo "[2/3] disable bunker mode (restores launch.json)"
$SSH '/data/opt/bin/killswitch.sh off' || {
    rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "killswitch: backup missing - restore /data/quasar/launch.json.backup manually" >&2
        echo "            (refusing to write a template; that can brick the speaker)" >&2
    else
        echo "killswitch off failed (rc=$rc)" >&2
    fi
    exit 1
}

if [ "$DO_REBOOT" -eq 1 ]; then
    echo "[3/3] reboot"
    $SSH 'sync; reboot' || true
    echo "reboot sent; Alice will come back on next boot"
else
    echo "[3/3] skipping reboot (pass --reboot to bring Alice back now)"
    echo "      run: $0 $HOST $PORT --reboot"
fi

echo "done"
echo "binaries left in /data/opt/bin, config in /data/opt/etc/buttonsd.conf"