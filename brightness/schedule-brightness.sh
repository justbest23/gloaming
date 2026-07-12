#!/bin/bash
# schedule-brightness.sh
# Duskwatch's actual redshift/gammastep equivalent: fades both brightness
# and color temperature together on a schedule, since Wayland clients can't
# set gamma tables directly and Redshift/gammastep don't work here at all.
#
# If a manual day/night override is set (see set-mode.sh), applies that and
# stops - this is what makes the tray widgets' mode switch actually stick
# instead of getting overwritten by the next periodic timer tick. Otherwise
# the fade is anchored to END at the scheduled boundary (like a real dusk/
# dawn transition), not start there - so it runs from (boundary -
# FADE_DURATION) up to boundary. That window is adaptive: if we're triggered
# less than FADE_DURATION before the boundary (periodic checks only run
# every few minutes, or the schedule was just edited close to the boundary),
# the fade compresses to whatever time is actually left instead of waiting
# for the next boundary to start a full-length fade. Just after a boundary
# (within ONTIME_WINDOW) we snap quickly, since we should already be at
# target; long after it - PC was off, late login - we also just snap.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

apply() {
    local pct=$1 temp=$2 duration=$3
    ./fade-temperature.sh "$temp" "$duration" &
    ./fade-brightness.sh "$pct" "$duration"
    wait
}

mode=$(get_mode)
if [[ "$mode" == "day" ]]; then
    apply "$NORMAL_PCT" "$NORMAL_TEMP" "$SNAP_DURATION"
    exit 0
elif [[ "$mode" == "night" ]]; then
    apply "$DIMMED_PCT" "$DIMMED_TEMP" "$SNAP_DURATION"
    exit 0
fi

now=$(date +%s)
today=$(date +%Y-%m-%d)
evening_epoch=$(date -d "$today $EVENING_HOUR:00" +%s)
morning_epoch=$(date -d "$today $MORNING_HOUR:00" +%s)

# Boundaries in chronological order, assuming MORNING_HOUR < EVENING_HOUR:
# yesterday's evening -> today's morning -> today's evening -> tomorrow's morning.
epochs=( "$(( evening_epoch - 86400 ))" "$morning_epoch" "$evening_epoch" "$(( morning_epoch + 86400 ))" )
kinds=( evening morning evening morning )

# Walk forward to find the most recent boundary at/before now (prev) and the
# next one after it (next) - the array is sorted ascending so this is just a
# single pass.
prev_epoch=${epochs[0]}; prev_kind=${kinds[0]}
next_epoch=${epochs[3]}; next_kind=${kinds[3]}
for i in 0 1 2 3; do
    if (( epochs[i] <= now )); then
        prev_epoch=${epochs[i]}
        prev_kind=${kinds[i]}
    else
        next_epoch=${epochs[i]}
        next_kind=${kinds[i]}
        break
    fi
done

target_for() {
    # kind=evening means "transitioning to dimmed"; morning means "to normal".
    if [[ "$1" == evening ]]; then
        echo "$DIMMED_PCT $DIMMED_TEMP"
    else
        echo "$NORMAL_PCT $NORMAL_TEMP"
    fi
}

if (( now - prev_epoch <= ONTIME_WINDOW )); then
    read -r target temp_target <<< "$(target_for "$prev_kind")"
    duration=$SNAP_DURATION
elif (( next_epoch - now <= FADE_DURATION )); then
    read -r target temp_target <<< "$(target_for "$next_kind")"
    duration=$(( next_epoch - now ))
    (( duration < SNAP_DURATION )) && duration=$SNAP_DURATION
else
    read -r target temp_target <<< "$(target_for "$prev_kind")"
    duration=$SNAP_DURATION
fi

apply "$target" "$temp_target" "$duration"
