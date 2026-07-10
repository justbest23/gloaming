# Gloaming

Fullscreen-aware color temperature and scheduled screen brightness for KDE Plasma 6 on Wayland.

## Why this exists

On Wayland, clients can't set gamma tables directly, so tools like Redshift/gammastep don't work — KDE's built-in **Night Color** (KWin's `NightLightManager`) is the only thing that actually shifts color temperature. But Night Color has two gaps:

1. It doesn't exempt fullscreen windows (games, video), so it keeps shifting color temperature under them — there's no built-in way to pause it automatically for a fullscreen app ([KDE wishlist bug 487304](https://bugs.kde.org/show_bug.cgi?id=487304)).
2. Plasma has no scheduled *brightness* control at all for external monitors (only an ambient-light-sensor auto-brightness for laptop panels, and nothing over DDC/CI for desktop displays).

Gloaming fills both gaps, plus a tray widget for manual override.

## Components

### `kwin-scripts/nightcolor-fullscreen-inhibit`

A KWin script that watches for fullscreen windows — both true fullscreen (`_NET_WM_STATE_FULLSCREEN`) and borderless-fullscreen (many game engines just show an undecorated window sized to the output without setting the fullscreen hint) — and calls KWin's `org.kde.KWin.NightLight` D-Bus `inhibit()`/`uninhibit()` methods accordingly, the same mechanism video players use to suppress Night Color during playback.

### `brightness/`

- `lib-config.sh` — shared config loader plus helpers for KDE's `org.kde.ScreenBrightness` D-Bus API (`org.kde.Solid.PowerManagement`, objects `/org/kde/ScreenBrightness/displayN`). This is the same interface System Settings and the hardware brightness keys use, and it transparently covers both real DDC/CI monitors and KWin's software-brightness fallback for displays where DDC/CI doesn't work at all — no need to shell out to `ddcutil` directly, and no bus numbers to configure.
- `fade-brightness.sh <percent> <seconds>` — smoothly fades every display to a target brightness, applying each display's `FLOOR_<display>`/`CEIL_<display>` calibration from `gloaming.conf` so a shared percentage can look visually consistent across monitors with very different raw ranges.
- `schedule-brightness.sh` — computes the correct brightness target from the current time of day and calls `fade-brightness.sh`. Distinguishes an on-time trigger (does a slow ~20 min fade) from a catch-up trigger — e.g. the PC was off at 19:00 and logs in at 9am the next day, or you just edited the schedule to a time already in the past — where it snaps to the target in ~10s instead of doing a slow fade hours after the fact.
- `fullscreen-brightness-watch.sh` — watches the `inhibited` property on `org.kde.KWin.NightLight` (set by the KWin script above) and snaps brightness to full while a fullscreen app is active, restoring the scheduled level when it isn't.

### `systemd/`

User-level systemd units wiring the above into your session:
- `gloaming-brightness-schedule.timer` / `.service` — fires at the configured evening/morning times (edit the `OnCalendar=` lines), `Persistent=true` and `OnStartupSec=30` so a missed trigger (PC off, late login) still gets caught up correctly on next session start.
- `gloaming-fullscreen-brightness-watch.service` — the long-running watcher daemon.

### `plasmoid/`

A native Plasma 6 tray applet for manual override: a brightness slider (instant, via `set-brightness-live.sh`) and a color-temperature slider that live-previews via `NightLight.preview()`/`stopPreview()` the same way KDE's own Night Color KCM slider does — dragging it changes color temperature immediately, and closing the widget reverts to whatever the schedule says. Brightness changes made this way persist (they're just the current brightness) rather than reverting.

### `tray-app/`

A standalone Python tray app offering the same controls outside of Plasma's widget system, kept in sync with the Plasmoid. **Work in progress.**

## Requirements

- KDE Plasma 6 (6.3+, for `org.kde.ScreenBrightness`), Wayland session
- `kwriteconfig6`, `kpackagetool6`, `gdbus` (part of a standard Plasma 6 install)

## Install

```
./install.sh
```

This symlinks the KWin script into `~/.local/share/kwin/scripts/`, the systemd units into `~/.config/systemd/user/`, and copies the default config to `~/.config/gloaming/gloaming.conf` if it doesn't already exist — so edits in this repo (or to your config) take effect without reinstalling. It does **not** enable any systemd timers/services for you — see the printed instructions to opt in.

Edit `~/.config/gloaming/gloaming.conf` for your schedule, brightness levels, and per-display calibration.

## Known limitations

- KWin's Night Color inhibitor is cookie-based and, in testing, only the original calling connection could reliably release its own inhibit — if a script/process holding an inhibit dies uncleanly, Night Color can get stuck inhibited until you log out and back in.
- The `SetBrightness` OSD-suppression flag (`flags=1`) was found empirically, not from documentation — it could change in a future Plasma release.
