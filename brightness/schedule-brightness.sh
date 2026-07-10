#!/bin/bash
# schedule-brightness.sh
# Determines the brightness target from the current time of day (reading
# gloaming.conf fresh each run, so schedule edits apply on the next periodic
# check without restarting anything) and fades to it. If we're firing near
# the actual scheduled boundary we do a slow fade; if we're catching up long
# after it - PC was off, late login, or the user just edited the schedule to
# a time already in the past - we snap to the target quickly instead.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

now=$(date +%s)
today=$(date +%Y-%m-%d)
hour=$(date +%-H)
evening_epoch=$(date -d "$today $EVENING_HOUR:00" +%s)
morning_epoch=$(date -d "$today $MORNING_HOUR:00" +%s)

if (( hour >= EVENING_HOUR )); then
    target=$DIMMED_PCT
    boundary=$evening_epoch
elif (( hour < MORNING_HOUR )); then
    target=$DIMMED_PCT
    boundary=$(( evening_epoch - 86400 ))
else
    target=$NORMAL_PCT
    boundary=$morning_epoch
fi

elapsed=$(( now - boundary ))
if (( elapsed <= ONTIME_WINDOW )); then
    duration=$FADE_DURATION
else
    duration=$SNAP_DURATION
fi

exec ./fade-brightness.sh "$target" "$duration"
