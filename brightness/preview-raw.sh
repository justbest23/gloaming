#!/bin/bash
# preview-raw.sh <display> <percent>
# Sets a single display's brightness directly to PERCENT of its own raw
# range, bypassing FLOOR/CEIL calibration entirely - used by the calibration
# dialog so dragging the Floor/Ceil fields previews the actual effect live
# on that one monitor.
set -euo pipefail
cd "$(dirname "$0")"
source lib-config.sh

DISPLAY_ID=$1
PCT=$2
max=$(sb_get "$DISPLAY_ID" MaxBrightness)
[[ -n "$max" ]] && sb_set "$DISPLAY_ID" $(( max * PCT / 100 ))
