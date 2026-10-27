#!/bin/sh
# uninstall-buttonsd.sh - stop and remove buttonsd autostart from the station.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOST=${ST_HOST:-192.168.10.185}
PORT=${ST_PORT:-2222}
SSH="ssh -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$HOST"
"$HERE/helpers/st-wait.sh" 300 || exit 1
$SSH '
    /etc/init.d/S98buttonsd stop 2>/dev/null
    mount -o remount,rw / || exit 1
    rm -f /etc/init.d/S98buttonsd /etc/init.d/S50ledoff /etc/init.d/S05ledoff
    sync
    mount -o remount,ro /
    echo "init script removed"
    echo "binaries left in /data/opt/bin, config in /data/opt/etc/buttonsd.conf"
'
