#!/bin/bash
# fullscreen-brightness-watch.sh
# Watches org.kde.KWin.NightLight's "inhibited" property (set by the
# nightcolor-fullscreen-inhibit KWin script whenever a fullscreen/borderless
# window is active) and snaps monitor brightness to NORMAL_PCT while a game
# is fullscreen, restoring DIMMED_PCT when it isn't.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

RETRIES=3

ddc_setvcp() {
    local bus=$1 val=$2
    for _ in $(seq 1 "$RETRIES"); do
        if ddcutil -b "$bus" setvcp 10 "$val" >/dev/null 2>&1; then
            return 0
        fi
    done
    echo "gloaming: bus $bus failed to set brightness to $val after $RETRIES tries" >&2
}

apply_state() {
    local inhibited=$1
    local pct=$DIMMED_PCT
    [[ "$inhibited" == "true" ]] && pct=$NORMAL_PCT
    for bus in "${BUSES[@]}"; do
        ddc_setvcp "$bus" "$pct"
    done
}

get_inhibited() {
    gdbus call --session --dest org.kde.KWin \
        --object-path /org/kde/KWin/NightLight \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.KWin.NightLight inhibited 2>/dev/null |
        grep -o 'true\|false'
}

apply_state "$(get_inhibited)"

gdbus monitor --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight |
while read -r line; do
    if [[ "$line" == *PropertiesChanged*org.kde.KWin.NightLight* && "$line" == *inhibited* ]]; then
        state=$(echo "$line" | grep -o "'inhibited': <\(true\|false\)>" | grep -o 'true\|false')
        [[ -n "$state" ]] && apply_state "$state"
    fi
done
