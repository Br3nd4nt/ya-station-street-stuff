#!/bin/sh
# buttons_mute.sh - toggle Master volume on/off without maind
# Persists the pre-mute level in /data/opt/var/lib/buttonsd/mute.

VDIR=/data/opt/var/lib/buttonsd
VSTATE=$VDIR/volume
MSTATE=$VDIR/mute
mkdir -p "$VDIR"

cur_pct() {
    amixer sget Master 2>/dev/null | grep -o '[0-9][0-9]*%' | head -n1 | tr -d '%'
}

if [ -s "$MSTATE" ]; then
    vol=$(cat "$MSTATE")
    case "$vol" in ''|*[!0-9]*) vol=20 ;; esac
    amixer -q set Master "${vol}%" >/dev/null 2>&1
    rm -f "$MSTATE"
    echo "$vol" > "$VSTATE"
    logger -t buttonsd "unmuted (${vol}%)" 2>/dev/null
    echo "unmuted (${vol}%)"
    [ -x /data/opt/bin/buttons_led.sh ] && /data/opt/bin/buttons_led.sh bar "$vol"
else
    cur=$(cur_pct)
    [ -n "$cur" ] || cur=20
    echo "$cur" > "$MSTATE"
    amixer -q set Master 0% >/dev/null 2>&1
    logger -t buttonsd "muted (was ${cur}%)" 2>/dev/null
    echo "muted (was ${cur}%)"
    [ -x /data/opt/bin/buttons_led.sh ] && /data/opt/bin/buttons_led.sh mute
fi
