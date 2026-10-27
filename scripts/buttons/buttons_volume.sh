#!/bin/sh
# buttons_volume.sh - volume step + persistence + unmute (no maind)
# usage: buttons_volume.sh up|down|restore|status

CONF=/data/opt/etc/buttonsd.conf
VDIR=/data/opt/var/lib/buttonsd
VSTATE=$VDIR/volume
MSTATE=$VDIR/mute
mkdir -p "$VDIR"

step=5
if [ -r "$CONF" ]; then
    s=$(sed -n 's/^[[:space:]]*volume_step[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | tail -n1)
    [ -n "$s" ] && step=$s
fi

cur_pct() {
    amixer sget Master 2>/dev/null | grep -o '[0-9][0-9]*%' | head -n1 | tr -d '%'
}

set_pct() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -gt 100 ] && set -- 100
    amixer -q set Master "$1%" >/dev/null 2>&1
}

case "$1" in
    restore)
        if [ -s "$MSTATE" ]; then
            set_pct 0
            echo "restored muted"
        elif [ -s "$VSTATE" ]; then
            set_pct "$(cat "$VSTATE")"
            echo "restored volume $(cur_pct)%"
        else
            set_pct 20
            echo "default volume 20%"
        fi
        exit 0
        ;;
    status)
        echo "volume $(cur_pct)%"
        [ -s "$MSTATE" ] && echo "muted (saved $(cat "$MSTATE"))"
        exit 0
        ;;
    up|down)
        # If muted, restore the saved level first (acts as unmute).
        if [ -s "$MSTATE" ]; then
            saved=$(cat "$MSTATE")
            set_pct "$saved"
            rm -f "$MSTATE"
        fi
        if [ "$1" = up ]; then
            amixer -q set Master "${step}%+" >/dev/null 2>&1
        else
            amixer -q set Master "${step}%-" >/dev/null 2>&1
        fi
        cur=$(cur_pct)
        [ -n "$cur" ] && echo "$cur" > "$VSTATE"
        logger -t buttonsd "volume $1 -> ${cur}%" 2>/dev/null
        echo "volume $1 -> ${cur}%"
        [ -x /data/opt/bin/buttons_led.sh ] && /data/opt/bin/buttons_led.sh bar "$cur"
        ;;
    *)
        echo "usage: $0 {up|down|restore|status}" >&2
        exit 1
        ;;
esac
