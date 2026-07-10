# lib-config.sh - shared config loader, sourced by the brightness scripts.
EVENING_HOUR=19
MORNING_HOUR=7
DIMMED_PCT=30
NORMAL_PCT=100
BUSES="5 7"
FADE_DURATION=1200
SNAP_DURATION=10
ONTIME_WINDOW=300

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/gloaming/gloaming.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^[A-Z_]+=' "$CONFIG_FILE")
fi
read -ra BUSES <<< "$BUSES"
