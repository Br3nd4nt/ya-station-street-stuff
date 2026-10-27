#!/bin/sh
# install-buttonsd.sh - deploy standalone button daemon to the station.
# Run from the repo root on the Mac. Safe to re-run. Handles flaky wifi.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
HOST=${ST_HOST:-192.168.10.185}
PORT=${ST_PORT:-2222}
SSH="ssh -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$HOST"

wait_station() {
    "$HERE/helpers/st-wait.sh" 300 || exit 1
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

echo "[1/5] build check"
[ -x "$ROOT/bin/buttonsd" ] || { echo "bin/buttonsd missing; build it first" >&2; exit 1; }

echo "[2/5] push files"
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

echo "[3/5] install init scripts"
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

echo "[4/5] start"
wait_station
$SSH '/etc/init.d/S98buttonsd restart; sleep 1; /etc/init.d/S98buttonsd status' || true

echo "[5/5] log"
$SSH 'tail -n 20 /data/opt/var/log/buttonsd.log 2>/dev/null' || true
echo "done"
