#!/bin/sh
# buttons_playpause.sh - play/pause/next/prev via spotiya
# used by button daemon: toggle / next / previous

SPOTIYA=/data/opt/spotify-connect/spotiya
LED=/data/opt/bin/buttons_led.sh
ACT="${1:-toggle}"

log() {
    logger -t buttonsd "play_pause[$ACT]: $*" 2>/dev/null
    echo "play_pause[$ACT]: $*"
}

case "$ACT" in
    toggle)
        if [ -x "$SPOTIYA" ]; then
            out=$("$SPOTIYA" --toggle 2>&1)
            rc=$?
            log "rc=$rc $out"
        else
            log "spotiya not found"
        fi
        [ -x "$LED" ] && "$LED" playpause
        ;;
    next)
        if [ -x "$SPOTIYA" ]; then
            out=$("$SPOTIYA" --next 2>&1)
            rc=$?
            log "rc=$rc $out"
        else
            log "spotiya not found"
        fi
        [ -x "$LED" ] && "$LED" playpause2
        ;;
    previous|prev)
        if [ -x "$SPOTIYA" ]; then
            out=$("$SPOTIYA" --previous 2>&1)
            rc=$?
            log "rc=$rc $out"
        else
            log "spotiya not found"
        fi
        [ -x "$LED" ] && "$LED" playpause3
        ;;
    *)
        if [ -x "$SPOTIYA" ]; then
            out=$("$SPOTIYA" --toggle 2>&1)
            rc=$?
            log "rc=$rc $out"
        else
            log "spotiya not found"
        fi
        [ -x "$LED" ] && "$LED" playpause
        ;;
esac

exit 0
