#!/bin/bash
# set-config.sh KEY VALUE
# Updates (or appends) a top-level KEY=VALUE line in duskwatch.conf. Used by
# the tray widgets' quick-settings fields (schedule hours, dim/normal
# percentages, fade duration/style) so they can be adjusted without
# hand-editing the file. VALUE is restricted to alphanumerics/underscore/
# dot/hyphen (covers plain integers and enum strings like smooth/stepped and
# active-screen/all) - no shell metacharacters, since it goes through sed -
# this is only meant for the small set of plain settings the widgets expose,
# not free text.
set -euo pipefail
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/duskwatch/duskwatch.conf"
KEY=$1
VALUE=$2

[[ "$KEY" =~ ^[A-Z_][A-Za-z0-9_]*$ ]] || { echo "invalid key" >&2; exit 1; }
[[ "$VALUE" =~ ^[A-Za-z0-9_,.-]+$ ]] || { echo "invalid value" >&2; exit 1; }

mkdir -p "$(dirname "$CONFIG_FILE")"
touch "$CONFIG_FILE"
if grep -q "^${KEY}=" "$CONFIG_FILE"; then
    sed -i "s/^${KEY}=.*/${KEY}=${VALUE}/" "$CONFIG_FILE"
else
    echo "${KEY}=${VALUE}" >> "$CONFIG_FILE"
fi
