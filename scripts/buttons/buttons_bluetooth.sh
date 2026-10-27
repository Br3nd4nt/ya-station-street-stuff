#!/bin/sh
# buttons_bluetooth.sh - put the station into Bluetooth pairing mode.
# Works without maind: powers the adapter, enables pairable/discoverable
# for 120 seconds and gives blue LED feedback.

LED=/data/opt/bin/buttons_led.sh
TIMEOUT_SEC=120

log() {
    logger -t buttonsd "bluetooth: $*" 2>/dev/null
    echo "bluetooth: $*"
}

if ! command -v bluetoothctl >/dev/null 2>&1; then
    log "bluetoothctl not found"
    exit 1
fi

bluetoothctl power on >/dev/null 2>&1
bluetoothctl pairable on >/dev/null 2>&1
# BlueZ supports discoverable-timeout; fall back to a background timer.
if ! bluetoothctl discoverable-timeout "$TIMEOUT_SEC" >/dev/null 2>&1; then
    ( sleep "$TIMEOUT_SEC"; bluetoothctl discoverable off >/dev/null 2>&1 ) &
fi
bluetoothctl discoverable on >/dev/null 2>&1

state=$(bluetoothctl show 2>/dev/null | grep -E "Powered:|Discoverable:" | tr -d '\t')
log "pairing mode ${TIMEOUT_SEC}s ${state}"

[ -x "$LED" ] && "$LED" bluetooth
exit 0
