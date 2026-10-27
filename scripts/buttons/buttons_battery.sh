#!/bin/sh
# buttons_battery.sh - show battery level on the 4 charge LEDs without maind
# Also logs the percentage taken from the ip2366 charger.

CAP=/sys/devices/virtual/ip2366_cls/ip2366_charger/capacity
LED=/data/opt/bin/buttons_led.sh

cap=$(cat "$CAP" 2>/dev/null)
case "$cap" in
    ''|*[!0-9]*) cap=0 ;;
esac

logger -t buttonsd "battery ${cap}%" 2>/dev/null
echo "battery ${cap}%"

if [ -x "$LED" ]; then
    "$LED" battery "$cap" 2
else
    sleep 2
fi
