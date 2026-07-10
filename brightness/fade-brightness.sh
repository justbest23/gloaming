#!/bin/bash
# fade-brightness.sh <target_percent> <duration_seconds>
# Fades all configured DDC/CI monitors to TARGET_PERCENT brightness over DURATION seconds.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}
STEPS=$(( DURATION < 30 ? DURATION : 30 ))
(( STEPS < 1 )) && STEPS=1
RETRIES=3

ddc_getvcp() {
    local bus=$1
    for _ in $(seq 1 "$RETRIES"); do
        local out
        if out=$(ddcutil -b "$bus" getvcp 10 --terse 2>/dev/null) && [[ "$out" == VCP\ 10\ C* ]]; then
            echo "$out"
            return 0
        fi
    done
    return 1
}

ddc_setvcp() {
    local bus=$1 val=$2
    for _ in $(seq 1 "$RETRIES"); do
        if ddcutil -b "$bus" setvcp 10 "$val" >/dev/null 2>&1; then
            return 0
        fi
    done
    echo "gloaming: bus $bus failed to set brightness to $val after $RETRIES tries" >&2
    return 1
}

declare -A CURRENT MAX TARGET_RAW
for bus in "${BUSES[@]}"; do
    if out=$(ddc_getvcp "$bus"); then
        read -r _ _ _ current max <<< "$out"
        CURRENT[$bus]=$current
        MAX[$bus]=$max
        TARGET_RAW[$bus]=$(( max * TARGET / 100 ))
    else
        echo "gloaming: bus $bus not responding, skipping" >&2
    fi
done

all_at_target=true
for bus in "${!CURRENT[@]}"; do
    (( CURRENT[$bus] != TARGET_RAW[$bus] )) && all_at_target=false
done
"$all_at_target" && exit 0

STEP_SLEEP=$(awk "BEGIN { printf \"%f\", $DURATION / $STEPS }")

for i in $(seq 1 "$STEPS"); do
    for bus in "${!CURRENT[@]}"; do
        diff=$(( TARGET_RAW[$bus] - CURRENT[$bus] ))
        val=$(( CURRENT[$bus] + diff * i / STEPS ))
        ddc_setvcp "$bus" "$val"
    done
    sleep "$STEP_SLEEP"
done
