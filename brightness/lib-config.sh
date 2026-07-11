# lib-config.sh - shared config loader and org.kde.ScreenBrightness helpers,
# sourced by the brightness scripts.
EVENING_HOUR=19
MORNING_HOUR=7
DIMMED_PCT=30
NORMAL_PCT=100
DISPLAYS=""
FADE_DURATION=1200
FADE_STYLE=smooth
FADE_STEP_MINUTES=5
SNAP_DURATION=10
ONTIME_WINDOW=300

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/gloaming/gloaming.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^[A-Z_][A-Za-z0-9_]*=' "$CONFIG_FILE")
fi

# Runtime override state (day/night/schedule), separate from gloaming.conf
# since it's set by the tray widgets rather than hand-edited - see
# set-mode.sh. Defaults to "schedule" (pure time-of-day behavior) if unset.
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/gloaming/state"
get_mode() {
    local mode
    mode=$(grep '^MODE=' "$STATE_FILE" 2>/dev/null | tail -1)
    mode=${mode#MODE=}
    echo "${mode:-schedule}"
}

SB_DEST=org.kde.Solid.PowerManagement
SB_IFACE=org.kde.ScreenBrightness.Display

sb_displays() {
    if [[ -n "$DISPLAYS" ]]; then
        echo "$DISPLAYS"
        return
    fi
    gdbus call --session --dest "$SB_DEST" \
        --object-path /org/kde/ScreenBrightness \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.ScreenBrightness DisplaysDBusNames 2>/dev/null |
        grep -o "'[^']*'" | tr -d "'"
}

sb_get() {
    local display=$1 prop=$2
    gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method org.freedesktop.DBus.Properties.Get "$SB_IFACE" "$prop" 2>/dev/null |
        grep -o '[0-9]\+'
}

sb_set() {
    local display=$1 val=$2
    # flags=1 suppresses the brightness OSD - confirmed empirically, KDE
    # doesn't document this bit locally. Without it, a 30-step fade pops the
    # OSD on every single step for the whole duration of the fade.
    gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method "$SB_IFACE.SetBrightness" "$val" 1 >/dev/null 2>&1
}

# Per-display calibration: monitors differ wildly in perceived brightness at
# the same raw percentage, so a schedule target like 30% is mapped through
# each display's own FLOOR_<display>/CEIL_<display> range (default 0/100)
# rather than applied to the raw 0-100 scale directly. Set these in
# gloaming.conf, e.g. FLOOR_display1=20 CEIL_display1=90, once you've found
# values that visually match across your monitors.
sb_calibrated_pct() {
    local display=$1 pct=$2
    local floor_var="FLOOR_$display" ceil_var="CEIL_$display"
    local floor=${!floor_var:-0} ceil=${!ceil_var:-100}
    echo $(( floor + (ceil - floor) * pct / 100 ))
}
