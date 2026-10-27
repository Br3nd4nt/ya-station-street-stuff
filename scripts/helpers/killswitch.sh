#!/bin/sh
# killswitch.sh - bunker mode for the station.
#
# Bunker mode replaces /system/vendor/quasar/launch.json with an empty
# task list so maind/platformd never start. quasar_launcher2 keeps running
# as the watchdog, but Alice never connects to Yandex cloud.
#
# Usage: killswitch.sh {on|off|status}
#   on|enable    enable bunker mode (backs up launch.json once)
#   off|disable  restore the original launch.json from backup
#   status       report current mode
#
# Exit codes:
#   0 ok, 1 usage/remount error, 2 backup missing on disable
set -u

LAUNCH_JSON=${LAUNCH_JSON:-/system/vendor/quasar/launch.json}
BACKUP_JSON=${BACKUP_JSON:-/data/quasar/launch.json.backup}
BUNKER_JSON='{
  "nodes": [
    {
      "name": "main",
      "root": ".",
      "tasks": []
    }
  ]
}'

log() { echo "[killswitch] $*"; }
die() { echo "[killswitch] ERROR: $*" >&2; exit 1; }

remount_rw() { mount -o remount,rw / || die "remount rw failed"; }
remount_ro() { sync; mount -o remount,ro / || die "remount ro failed"; }

status() {
    if ps | grep -E 'maind|platformd' | grep -v grep >/dev/null 2>&1; then
        log "STATUS: normal mode - Quasar active, Alice connected to cloud."
        return 0
    fi
    log "STATUS: BUNKER MODE - Quasar disabled, speaker isolated from Yandex."
    return 0
}

enable_bunker() {
    log "enabling bunker mode..."
    remount_rw

    mkdir -p "$(dirname "$BACKUP_JSON")" || die "cannot create backup dir"

    # Back up exactly once, before we ever touch launch.json.
    if [ ! -f "$BACKUP_JSON" ] && [ -f "$LAUNCH_JSON" ]; then
        cp -f "$LAUNCH_JSON" "$BACKUP_JSON" || die "backup failed"
        log "backup saved to $BACKUP_JSON"
    elif [ ! -f "$BACKUP_JSON" ]; then
        die "no backup and no $LAUNCH_JSON to back up"
    else
        log "backup already exists, keeping it"
    fi

    printf '%s\n' "$BUNKER_JSON" > "$LAUNCH_JSON" || die "writing launch.json failed"
    remount_ro
    log "bunker mode active. reboot to apply."
    return 0
}

disable_bunker() {
    log "disabling bunker mode..."
    if [ ! -f "$BACKUP_JSON" ]; then
        # Do NOT write a template - a wrong launch.json can brick the speaker.
        echo "[killswitch] ERROR: $BACKUP_JSON missing; refusing to guess launch.json" >&2
        return 2
    fi
    remount_rw
    cp -f "$BACKUP_JSON" "$LAUNCH_JSON" || die "restore failed"
    remount_ro
    log "normal mode restored. reboot to apply."
    return 0
}

case "${1:-}" in
    on|enable)   enable_bunker ;;
    off|disable) disable_bunker ;;
    status)      status ;;
    *)
        echo "usage: $0 {on|off|status}" >&2
        exit 1
        ;;
esac