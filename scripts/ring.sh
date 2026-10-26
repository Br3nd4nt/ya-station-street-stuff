#!/bin/sh
# ring.sh - RGB ring control for Yandex Station Street (mango)
#
# based on https://github.com/Marker284/yandex-station-extended/blob/main/contrib/ring.sh
# for station mini

LEDS=/sys/class/leds

BACKUP_PATH=/tmp/led_triggers

SEGS="0 1 2"

CHARGE_SEGS="0 1 2 3"

SNAKE_SEGS="0 1 2 3 2 1"


COLS="red green blue"

delay=0.07

backup() { mkdir -p $BACKUP_PATH; for l in $(ls $LEDS); do cat $LEDS/$l/trigger > $BACKUP_PATH/$l-trigger.backup 2>/dev/null; done; }

restore() { for l in $(ls $LEDS); do cat $BACKUP_PATH/$l-trigger.backup > $LEDS/$l/trigger 2>/dev/null; done; }

raw(){ echo "$3" > "$LEDS/mango:$1:logo$2/brightness" 2>/dev/null; }

off(){ for c in $COLS; do for n in $SEGS; do raw "$c" "$n" 0; done; done; }

seg(){ raw red "$1" "$2"; raw green "$1" "$3"; raw blue "$1" "$4"; }

fill(){ for n in $SEGS; do seg "$n" "$1" "$2" "$3"; done; }

fill_delayed(){ for n in $SEGS; do seg "$n" "$1" "$2" "$3"; sleep $delay; done; }

raw_charge(){ echo "$2" > "$LEDS/mango:red:charge$1/brightness" 2>/dev/null; }

on_charge(){ raw_charge $1 255 2>/dev/null; }
off_charge(){ raw_charge $1 0 2>/dev/null; }
off_all_charges(){ for l in $CHARGE_SEGS; do off_charge $l ; done; }

cmd="$1"; [ $# -ge 1 ] && shift

backup

case "$cmd" in

  off)
    off
    ;;

  fill)
    fill "${1:-0}" "${2:-0}" "${3:-0}"
    ;;

  seg)
    seg "${1:-1}" "${2:-0}" "${3:-0}" "${4:-0}"
    ;;

  rainbow)
    cnt="${1:-10}"
    i=0

    while [ "$i" -lt "$cnt" ]; do
    fill_delayed 255 0   0;   sleep $delay
    fill_delayed 255 32  0;   sleep $delay
    fill_delayed 255 64  0;   sleep $delay
    fill_delayed 255 96  0;   sleep $delay
    fill_delayed 255 128 0;   sleep $delay
    fill_delayed 255 160 0;   sleep $delay
    fill_delayed 204 179 0;   sleep $delay
    fill_delayed 153 198 0;   sleep $delay
    fill_delayed 102 217 0;   sleep $delay
    fill_delayed 51  236 0;   sleep $delay
    fill_delayed 0   255 0;   sleep $delay
    fill_delayed 0   240 51;  sleep $delay
    fill_delayed 0   225 102; sleep $delay
    fill_delayed 0   210 153; sleep $delay
    fill_delayed 0   195 204; sleep $delay
    fill_delayed 0   180 255; sleep $delay
    fill_delayed 16  144 255; sleep $delay
    fill_delayed 32  108 255; sleep $delay
    fill_delayed 48  72  255; sleep $delay
    fill_delayed 64  36  255; sleep $delay
    fill_delayed 80  0   255; sleep $delay
    fill_delayed 80  0 255;   sleep $delay
    fill_delayed 115 0 204;   sleep $delay
    fill_delayed 150 0 153;   sleep $delay
    fill_delayed 185 0 102;   sleep $delay
    fill_delayed 220 0 51;    sleep $delay
    fill_delayed 255 0 0;     sleep $delay

      i=$((i+1))
    done

    off
    ;;

  chase)
    cnt="${1:-20}"
    i=0
    off
    while [ "$i" -lt "$cnt" ]; do
      for n in $SEGS; do
        seg "$n" 0 180 255
        sleep 0.12
        off
      done

      i=$((i+1))
    done

    off
    ;;

  blink)
    r="${1:-255}"
    g="${2:-0}"
    b="${3:-0}"
    ms="${4:-250}"
    cnt="${5:-10}"

    d=$(awk "BEGIN{print $ms/1000}")
    i=0

    while [ "$i" -lt "$cnt" ]; do
      fill "$r" "$g" "$b"
      sleep "$d"

      off
      sleep "$d"

      i=$((i+1))
    done
    ;;

  breathe)[
    r="${1:-0}"
    g="${2:-180}"
    b="${3:-255}"
    cnt="${4:-5}"
    i=0

    while [ "$i" -lt "$cnt" ]; do

      v=0
      while [ "$v" -le 255 ]; do
        fill $((r*v/255)) $((g*v/255)) $((b*v/255))
        sleep 0.02
        v=$((v+17))
      done

      v=255
      while [ "$v" -ge 0 ]; do
        fill $((r*v/255)) $((g*v/255)) $((b*v/255))
        sleep 0.02
        v=$((v-17))
      done

      i=$((i+1))
    done

    off
    ;;

  snake)
    cnt="${1:-20}"
    i=0
    off_all_charges
    while [ "$i" -lt "$cnt" ]; do
      for n in $SNAKE_SEGS; do
        on_charge $n
        sleep 0.12
        off_charge $n
      done

      i=$((i+1))
    done

    off
    ;;

  # Display usage information if the command is missing or unrecognized.
  *)
    echo "ring.sh - RGB ring control (yandexmango)"
    echo "  ring.sh fill R G B         whole ring to color (0-255)"
    echo "  ring.sh seg N R G B        one segment (N=1..3)"
    echo "  ring.sh off                all off"
    echo "  ring.sh rainbow [cycles]   color cycle"
    echo "  ring.sh chase [cycles]     running dot"
    echo "  ring.sh snake [cycles]     running dot on changer"
    echo "  ring.sh breathe R G B [c]  smooth fade in/out"
    echo "  ring.sh blink R G B [ms] [count]"
    ;;
esac

restore