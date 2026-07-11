#!/bin/bash
# set-mode.sh day|night|schedule
# Sets the manual override mode used by schedule-brightness.sh and applies
# it immediately. "day"/"night" pin brightness regardless of time of day
# until switched back; "schedule" clears the override and resumes normal
# time-of-day behavior.
set -euo pipefail
cd "$(dirname "$0")"
source lib-config.sh

MODE=$1
case "$MODE" in
    day|night|schedule) ;;
    *) echo "usage: set-mode.sh day|night|schedule" >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$STATE_FILE")"
echo "MODE=$MODE" > "$STATE_FILE"

case "$MODE" in
    day)      ./fade-brightness.sh "$NORMAL_PCT" "$SNAP_DURATION" ;;
    night)    ./fade-brightness.sh "$DIMMED_PCT" "$SNAP_DURATION" ;;
    schedule) ./schedule-brightness.sh ;;
esac
