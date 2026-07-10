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

- `fade-brightness.sh <percent> <seconds>` — smoothly fades all configured monitors (by DDC/CI I2C bus number) to a target brightness via `ddcutil setvcp 10`, with retries for flaky DDC hardware.
- `schedule-brightness.sh` — computes the correct brightness target from the current time of day and calls `fade-brightness.sh`. Distinguishes an on-time trigger (does a slow ~20 min fade) from a catch-up trigger — e.g. the PC was off at 19:00 and logs in at 9am the next day — where it snaps to the target in ~10s instead of doing a slow fade hours after the fact.
- `fullscreen-brightness-watch.sh` — watches the `inhibited` property on `org.kde.KWin.NightLight` (set by the KWin script above) and snaps brightness to full while a fullscreen app is active, restoring the scheduled level when it isn't.

### `systemd/`

User-level systemd units wiring the above into your session:
- `gloaming-brightness-schedule.timer` / `.service` — fires at the configured evening/morning times (edit the `OnCalendar=` lines), `Persistent=true` and `OnStartupSec=30` so a missed trigger (PC off, late login) still gets caught up correctly on next session start.
- `gloaming-fullscreen-brightness-watch.service` — the long-running watcher daemon.

### `plasmoid/` and `tray-app/`

Two tray widgets for manual override of Night Color temperature and brightness — a native Plasma 6 applet and a standalone Python tray app, kept in sync with each other. **Work in progress.**

## Requirements

- KDE Plasma 6, Wayland session
- `ddcutil` (and the `i2c-dev` kernel module loaded) for monitors that support DDC/CI — not all monitors do, and some are DDC-flaky (the scripts retry automatically)
- `kwriteconfig6`, `kpackagetool6` (part of a standard Plasma 6 install)

## Install

```
./install.sh
```

This symlinks the KWin script into `~/.local/share/kwin/scripts/` and the systemd units into `~/.config/systemd/user/`, so edits in this repo take effect without reinstalling. It does **not** enable any systemd timers/services for you — see the printed instructions to opt in.

Before enabling brightness scripts, edit `brightness/fade-brightness.sh` and `fullscreen-brightness-watch.sh`'s `BUSES=(...)` array to match your own monitors' I2C bus numbers (`ddcutil detect`).

## Known limitations

- KWin's Night Color inhibitor is cookie-based and, in testing, only the original calling connection could reliably release its own inhibit — if a script/process holding an inhibit dies uncleanly, Night Color can get stuck inhibited until you log out and back in.
- Some monitors' DDC/CI implementations are flaky under sustained polling; the fade scripts retry each call but a monitor that fails DDC entirely (common on older displays) isn't supported.
