#!/bin/bash
# list-displays.sh
# Lists org.kde.ScreenBrightness displays with their label and current
# FLOOR_<display>/CEIL_<display> calibration (defaults 0/100), one per line,
# pipe-delimited: id|label|floor|ceil. Used by the tray widgets' calibration
# dialog.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

for display in $(sb_displays); do
    label=$(gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method org.freedesktop.DBus.Properties.Get "$SB_IFACE" Label 2>/dev/null |
        sed -n "s/.*'\(.*\)'.*/\1/p")
    floor_var="FLOOR_$display"
    ceil_var="CEIL_$display"
    floor=${!floor_var:-0}
    ceil=${!ceil_var:-100}
    echo "${display}|${label:-$display}|${floor}|${ceil}"
done
