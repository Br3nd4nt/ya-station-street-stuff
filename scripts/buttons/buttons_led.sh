#!/bin/sh
# buttons_led.sh - standalone LED control for buttonsd (mango)
#
# Controls the 3-segment Alice ring and the 4 charge LEDs directly through
# sysfs. In bunker mode it also stops the bootloader/i2c preboot animations
# (purple pulse + charge display) that normally continue until maind starts.
#
# usage:
#   buttons_led.sh init                 stop animations, detach triggers, all off
#   buttons_led.sh killanim             only stop logo/charge animations
#   buttons_led.sh off
#   buttons_led.sh fill R G B
#   buttons_led.sh pulse R G B [sec]
#   buttons_led.sh bar PCT              volume bar 0..100 on the ring
#   buttons_led.sh battery PCT [sec]    battery level on the 4 charge LEDs
#   buttons_led.sh mute                 solid red ring
#   buttons_led.sh bluetooth            blue pulse
#   buttons_led.sh playpause            green pulse

LEDS=/sys/class/leds
COLORS="red green blue white"

set_logo() {
    echo "$3" > "$LEDS/mango:$1:logo$2/brightness" 2>/dev/null
}

set_charge() {
    echo "$2" > "$LEDS/mango:red:charge$1/brightness" 2>/dev/null
}

detach_triggers() {
    for l in "$LEDS"/mango:*; do
        [ -d "$l" ] && echo none > "$l/trigger" 2>/dev/null
    done
}

killanim() {
    echo 0 > /sys/devices/platform/logo-animation/stop 2>/dev/null
    echo 0 > /sys/devices/platform/charge-animation/stop 2>/dev/null
}

off() {
    for c in $COLORS; do
        for n in 0 1 2; do set_logo "$c" "$n" 0; done
    done
    for n in 0 1 2 3; do set_charge "$n" 0; done
    echo 0 > "$LEDS/mango:charge:sync/brightness" 2>/dev/null
}

fill() {
    for n in 0 1 2; do
        set_logo red   "$n" "${1:-0}"
        set_logo green "$n" "${2:-0}"
        set_logo blue  "$n" "${3:-0}"
        set_logo white "$n" 0
    done
}

bar() {
    pct=${1:-0}
    case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
    [ "$pct" -gt 100 ] && pct=100
    off
    [ "$pct" -eq 0 ] && return 0
    if [ "$pct" -ge 67 ]; then
        r=0; g=255; b=0
    elif [ "$pct" -ge 34 ]; then
        r=255; g=160; b=0
    else
        r=255; g=0; b=0
    fi
    segs=$(( (pct + 33) / 34 ))
    [ "$segs" -gt 3 ] && segs=3
    n=0
    while [ "$n" -lt "$segs" ]; do
        set_logo red "$n" "$r"
        set_logo green "$n" "$g"
        set_logo blue "$n" "$b"
        n=$((n + 1))
    done
}

battery() {
    pct=${1:-0}
    hold=${2:-2}
    case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
    [ "$pct" -gt 100 ] && pct=100
    off
    segs=$(( (pct + 24) / 25 ))
    [ "$segs" -gt 4 ] && segs=4
    n=0
    while [ "$n" -lt 4 ]; do
        [ "$n" -lt "$segs" ] && set_charge "$n" 255
        n=$((n + 1))
    done
    sleep "$hold"
    off
}

case "$1" in
    init)
        killanim
        detach_triggers
        off
        ;;
    killanim) killanim ;;
    off) off ;;
    fill) fill "${2:-0}" "${3:-0}" "${4:-0}" ;;
    pulse)
        fill "${2:-0}" "${3:-0}" "${4:-0}"
        sleep "${5:-0.22}"
        off
        ;;
    bar) bar "${2:-0}" ;;
    battery) battery "${2:-0}" "${3:-2}" ;;
    mute)
        off
        fill 255 0 0
        ;;
    bluetooth)
        fill 0 60 255
        sleep 0.5
        off
        ;;
    playpause)
        fill 0 255 0
        sleep 0.25
        off
        ;;
    playpause2)
        # double click -> next track: two cyan flashes
        fill 0 180 255
        sleep 0.12
        off
        sleep 0.08
        fill 0 180 255
        sleep 0.12
        off
        ;;
    playpause3)
        # triple click -> previous track: three violet flashes
        n=0
        while [ "$n" -lt 3 ]; do
            fill 160 0 255
            sleep 0.1
            off
            sleep 0.07
            n=$((n + 1))
        done
        ;;
    *)
        echo "usage: $0 {init|killanim|off|fill|pulse|bar|battery|mute|bluetooth|playpause|playpause2|playpause3} ..." >&2
        exit 1
        ;;
esac
