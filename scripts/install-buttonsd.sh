#!/bin/sh
# install-buttonsd.sh - deploy standalone button daemon to the station.
# Run from the repo root on the Mac. Safe to re-run. Handles flaky wifi.
#
# The daemon needs maind/platformd to be dead, so this script enables
# bunker mode (via helpers/killswitch.sh) before pushing files.
#
# Usage: install-buttonsd.sh HOST [PORT] [--reboot]
#   HOST may be omitted only if $ST_HOST is set.
#   PORT defaults to 2222 (override with $ST_PORT).
#   --reboot  reboot the station at the end so bunker mode takes effect.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)

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

wait_station() {
    "$HERE/helpers/st-wait.sh" "$HOST" "$PORT" 300 || exit 1
}

push_file() {
    src=$1
    dst=$2
    mode=$3
    i=0
    while [ "$i" -lt 40 ]; do
        wait_station
        if cat "$src" | $SSH "mkdir -p '${dst%/*}'; cat > '$dst.tmp' && chmod '$mode' '$dst.tmp' && mv -f '$dst.tmp' '$dst'"; then
            echo "pushed $dst"
            return 0
        fi
        i=$((i + 1))
        echo "push $dst failed, retry $i..." >&2
        sleep 3
    done
    echo "giving up on $dst" >&2
    exit 1
}

echo "[1/7] build check"
[ -x "$ROOT/bin/buttonsd" ] || { echo "bin/buttonsd missing; build it first" >&2; exit 1; }

echo "[2/7] push files"
push_file "$ROOT/scripts/helpers/killswitch.sh" /data/opt/bin/killswitch.sh 755
push_file "$ROOT/bin/buttonsd"          /data/opt/bin/buttonsd 755
push_file "$ROOT/scripts/ring.sh"       /data/opt/bin/ring.sh 755
push_file "$ROOT/scripts/buttons/buttons_led.sh"     /data/opt/bin/buttons_led.sh 755
push_file "$ROOT/scripts/buttons/buttons_mute.sh"    /data/opt/bin/buttons_mute.sh 755
push_file "$ROOT/scripts/buttons/buttons_volume.sh"  /data/opt/bin/buttons_volume.sh 755
push_file "$ROOT/scripts/buttons/buttons_battery.sh" /data/opt/bin/buttons_battery.sh 755
push_file "$ROOT/scripts/buttons/buttons_playpause.sh" /data/opt/bin/buttons_playpause.sh 755
push_file "$ROOT/scripts/buttons/buttons_bluetooth.sh" /data/opt/bin/buttons_bluetooth.sh 755
push_file "$ROOT/system_files/buttonsd.conf" /data/opt/etc/buttonsd.conf 644
$SSH 'mkdir -p /data/opt/etc/buttons.d /data/opt/var/log /data/opt/var/run'

echo "[3/7] enable bunker mode (stops maind/platformd)"
wait_station
$SSH '/data/opt/bin/killswitch.sh on' || { echo "killswitch on failed" >&2; exit 1; }

echo "[4/7] install init scripts"
wait_station
cat "$ROOT/system_files/S98buttonsd" | $SSH '
    cat > /tmp/S98buttonsd.new || exit 1
    chmod 755 /tmp/S98buttonsd.new
    if cmp -s /tmp/S98buttonsd.new /etc/init.d/S98buttonsd; then
        echo "S98buttonsd unchanged"; exit 0
    fi
    mount -o remount,rw / || exit 1
    cp -f /tmp/S98buttonsd.new /etc/init.d/S98buttonsd
    chmod 755 /etc/init.d/S98buttonsd
    sync
    mount -o remount,ro /
    echo "S98buttonsd installed"
'
if [ $? -ne 0 ]; then echo "S98 buttonsd install failed" >&2; exit 1; fi
wait_station
cat "$ROOT/system_files/S50ledoff" | $SSH '
    cat > /tmp/S50ledoff.new || exit 1
    chmod 755 /tmp/S50ledoff.new
    if cmp -s /tmp/S50ledoff.new /etc/init.d/S50ledoff; then
        echo "S50ledoff unchanged"; exit 0
    fi
    mount -o remount,rw / || exit 1
    cp -f /tmp/S50ledoff.new /etc/init.d/S50ledoff
    chmod 755 /etc/init.d/S50ledoff
    sync
    mount -o remount,ro /
    echo "S50ledoff installed"
'
if [ $? -ne 0 ]; then echo "S50 ledoff install failed" >&2; exit 1; fi
wait_station
cat "$ROOT/system_files/S05ledoff" | $SSH '
    cat > /tmp/S05ledoff.new || exit 1
    chmod 755 /tmp/S05ledoff.new
    if cmp -s /tmp/S05ledoff.new /etc/init.d/S05ledoff; then
        echo "S05ledoff unchanged"; exit 0
    fi
    mount -o remount,rw / || exit 1
    cp -f /tmp/S05ledoff.new /etc/init.d/S05ledoff
    chmod 755 /etc/init.d/S05ledoff
    sync
    mount -o remount,ro /
    echo "S05ledoff installed"
'
if [ $? -ne 0 ]; then echo "S05 ledoff install failed" >&2; exit 1; fi

echo "[5/7] start"
wait_station
$SSH '/etc/init.d/S98buttonsd restart; sleep 1; /etc/init.d/S98buttonsd status' || true

echo "[6/7] log"
$SSH 'tail -n 20 /data/opt/var/log/buttonsd.log 2>/dev/null' || true

if [ "$DO_REBOOT" -eq 1 ]; then
    echo "[7/7] reboot"
    wait_station
    $SSH 'sync; reboot' || true
    echo "reboot sent; buttonsd will come up in bunker mode"
else
    echo "[7/7] skipping reboot (pass --reboot to apply bunker mode now)"
    echo "note: maind/platformd are still running until you reboot"
    echo "      run: $0 $HOST $PORT --reboot   or   ssh ... killswitch.sh status"
fi

echo "done"