#!/bin/bash
# fade-brightness.sh <target_percent> <duration_seconds>
# Fades all displays known to KDE's org.kde.ScreenBrightness D-Bus service to
# TARGET_PERCENT over DURATION seconds. This goes through the same interface
# System Settings and the brightness keys use, so it works uniformly whether
# a display is controlled via real DDC/CI or KWin's software brightness
# fallback (e.g. a monitor whose DDC/CI is flaky or unsupported).
#
# FADE_STYLE (from gloaming.conf) picks the shape of the transition:
#   smooth  (default) - 30 even micro-steps across DURATION, looks continuous
#   stepped            - fewer, larger jumps spaced FADE_STEP_MINUTES apart,
#                         however many of those intervals fit in DURATION
#                         (clamped to [1, 500] steps so a stray config value
#                         can't spin this into a runaway loop)
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}

if [[ "${FADE_STYLE:-smooth}" == "stepped" ]]; then
    STEP_SLEEP=$(awk "BEGIN { s = ${FADE_STEP_MINUTES:-5} * 60; if (s < 1) s = 1; printf \"%f\", s }")
    STEPS=$(awk "BEGIN { n = int($DURATION / $STEP_SLEEP + 0.5); if (n < 1) n = 1; if (n > 500) n = 500; print n }")
else
    STEPS=30
    STEP_SLEEP=$(awk "BEGIN { printf \"%f\", $DURATION / $STEPS }")
fi

declare -A CURRENT MAX TARGET_RAW
for display in $(sb_displays); do
    max=$(sb_get "$display" MaxBrightness)
    current=$(sb_get "$display" Brightness)
    if [[ -n "$max" && -n "$current" ]]; then
        CURRENT[$display]=$current
        MAX[$display]=$max
        TARGET_RAW[$display]=$(( max * $(sb_calibrated_pct "$display" "$TARGET") / 100 ))
    else
        echo "gloaming: $display not responding, skipping" >&2
    fi
done

all_at_target=true
for display in "${!CURRENT[@]}"; do
    (( CURRENT[$display] != TARGET_RAW[$display] )) && all_at_target=false
done
"$all_at_target" && exit 0

for i in $(seq 1 "$STEPS"); do
    for display in "${!CURRENT[@]}"; do
        diff=$(( TARGET_RAW[$display] - CURRENT[$display] ))
        val=$(( CURRENT[$display] + diff * i / STEPS ))
        sb_set "$display" "$val"
    done
    sleep "$STEP_SLEEP"
done
