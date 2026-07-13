# Duskwatch

A Redshift/gammastep replacement for KDE Plasma 6 on Wayland, plus scheduled screen brightness and a fullscreen-aware inhibitor for games.

## Why this exists

On Wayland, clients can't set gamma tables directly, so Redshift/gammastep don't work at all. KDE's built-in **Night Color** (KWin's `NightLightManager`) is the only thing on the system that can actually shift color temperature — but it has gaps Duskwatch fills:

1. Nothing on Plasma schedules color temperature *and* brightness together the way Redshift did — Duskwatch's own scheduler (`schedule-brightness.sh` + `fade-temperature.sh`) fades both in sync, driving KWin Night Color's "Constant" mode (the only persistent color-temperature control on Wayland — see `fade-temperature.sh` for why `preview()` doesn't work for this).
2. Night Color doesn't exempt fullscreen windows (games, video), so it keeps shifting color temperature under them — there's no built-in way to pause it automatically for a fullscreen app ([KDE wishlist bug 487304](https://bugs.kde.org/show_bug.cgi?id=487304)). Duskwatch's KWin script inhibits it for the duration.
3. Plasma has no scheduled *brightness* control at all for external monitors (only an ambient-light-sensor auto-brightness for laptop panels, and nothing over DDC/CI for desktop displays).

If you also have KDE's own Night Color enabled with its own schedule, the two can fight over color temperature between Duskwatch's periodic ticks — see Known limitations.

## Components

### `kwin-scripts/nightcolor-fullscreen-inhibit`

A KWin script that watches for fullscreen windows — both true fullscreen (`_NET_WM_STATE_FULLSCREEN`) and borderless-fullscreen (many game engines just show an undecorated window sized to the output without setting the fullscreen hint) — and has KWin's `org.kde.KWin.NightLight` inhibited/uninhibited accordingly, the same mechanism video players use to suppress Night Color during playback. A fullscreen window counts as long as it's visible (not minimized, not on another virtual desktop) — it doesn't have to be focused, so clicking over to a browser on another monitor doesn't un-pause anything while a game is still on show.

It doesn't call `inhibit()`/`uninhibit()` itself: KWin's JS `callDBus()` marshals every JS number as a signed int32 ([KDE bug 486024](https://bugs.kde.org/show_bug.cgi?id=486024), fix [kwin!5695](https://invent.kde.org/plasma/kwin/-/merge_requests/5695) still unmerged as of KWin 6.7.2), so `uninhibit(uint cookie)` never dispatches from script ("Could not find slot NightLightAdaptor::uninhibit") and the inhibit would get stuck forever. Instead the script sends the set of outputs that have a fullscreen window (a plain string, which marshals fine) to the helper below.

### `helper/nightlight-inhibit-helper.py`

A tiny D-Bus-activated service (`org.duskwatch.NightLightInhibit`) that holds the actual Night Color inhibit on the KWin script's behalf, making the correctly-typed `uint32` calls that KWin JS can't. Started on demand by the bus on first call — nothing to enable. Failure-safe by construction: KWin auto-releases an inhibitor when its bus connection disappears, so if the helper ever crashes while inhibiting, Night Color recovers on its own instead of sticking. It also republishes the KWin script's fullscreen-output set as a readable `FullscreenOutputs` property (comma-separated connector names, e.g. `DP-2`), which is what `fullscreen-brightness-watch.sh` keys per-screen brightness off. `NIGHTCOLOR_PAUSE_OUTPUTS` in `duskwatch.conf` (re-read on every fullscreen change) picks which screens' fullscreen windows actually trigger the Night Color pause — the pause is compositor-global when it fires (KWin has no per-output color temperature), but restricting the trigger to e.g. the main gaming monitor stops a fullscreen video on a side screen from un-warming the whole desktop.

### `brightness/`

- `lib-config.sh` — shared config loader plus helpers for KDE's `org.kde.ScreenBrightness` D-Bus API (`org.kde.Solid.PowerManagement`, objects `/org/kde/ScreenBrightness/displayN`). This is the same interface System Settings and the hardware brightness keys use, and it transparently covers both real DDC/CI monitors and KWin's software-brightness fallback for displays where DDC/CI doesn't work at all — no need to shell out to `ddcutil` directly, and no bus numbers to configure.
- `fade-brightness.sh <percent> <seconds>` — smoothly fades every display to a target brightness, applying each display's floor/ceiling calibration from `duskwatch.conf` (stable label-derived `FLOOR_<key>`/`CEIL_<key>` entries, with legacy positional `FLOOR_displayN` still honored) so a shared percentage can look visually consistent across monitors with very different raw ranges. Starting a fade kills any fade of the same kind still running (as does a manual slider drag via `set-brightness-live.sh`), so a timer tick, a mode switch, and a config edit can never fight each other write-for-write.
- `set-software-dimming.sh <displayN|connector> on|off` — forces KWin's software (gamma-based) brightness dimming for one display by disallowing DDC/CI on its output (`kscreen-doctor output.X.ddcCi.disallow`), or restores hardware DDC/CI control. KWin then force-enables its software SDR brightness fallback, which also makes a display with broken DDC/CI (re)appear in `org.kde.ScreenBrightness`. Software dimming scales RGB values compositor-side: it can go darker than the hardware range allows, but the backlight stays at full power, so it saves no energy. Persists across sessions.
- `fade-temperature.sh <kelvin> <seconds>` — the color-temperature half of the pair above, same timing so brightness and color move together. Pins Night Color to "Constant" mode and ramps `NightTemperature` in kwinrc via `kwriteconfig6 --notify` (KWin's nightlight plugin reloads settings through KConfigWatcher, not the generic `reconfigure`); KWin eases each change over ~2s, silently and persistently. `NightLight.preview()` is deliberately not used for schedules: as of KWin 6.7 every `preview()` call flashes the "Color Temperature Preview" OSD and arms a 15s auto-revert timer.
- `schedule-brightness.sh` — computes the correct brightness *and* color-temperature target from the current time of day and runs both fades together. Distinguishes an on-time trigger (does a slow fade, `FADE_DURATION`) from a catch-up trigger — e.g. the PC was off at 19:00 and logs in at 9am the next day, or you just edited the schedule to a time already in the past — where it snaps to the target in `SNAP_DURATION` instead of doing a slow fade hours after the fact.
- `fullscreen-brightness-watch.sh` — watches the helper's `FullscreenOutputs` property and snaps brightness to full while a fullscreen app is up, restoring the scheduled level when it goes away. By default (`FULLSCREEN_BRIGHTNESS_SCOPE=active-screen`) only the display(s) the fullscreen window is actually on get brightened — the others keep their dimmed level and are never touched; set `FULLSCREEN_BRIGHTNESS_SCOPE=all` (or untick the checkbox in the widgets' Settings) for the brighten-everything behavior. Note the Night Color pause is global regardless — KWin has no per-output color temperature.

### `systemd/`

User-level systemd units wiring the above into your session:
- `duskwatch-brightness-schedule.timer` / `.service` — wakes every 5 minutes (plus `OnStartupSec=30`, `Persistent=true`) and lets `schedule-brightness.sh` decide what to do; the actual evening/morning times live in `duskwatch.conf` (`EVENING_HOUR`/`EVENING_MINUTE`, `MORNING_HOUR`/`MORNING_MINUTE`), so schedule edits apply without touching the unit.
- `duskwatch-config-apply.path` / `.service` — watches `duskwatch.conf` and re-applies the schedule the moment the file changes (a widget writes it, or you save it from an editor), killing and superseding any fade already in progress. Without it, edits only land on the next timer tick, up to 5 minutes later.
- `duskwatch-fullscreen-brightness-watch.service` — the long-running watcher daemon.
- `duskwatch-nightlight-inhibit-helper.service` — the Night Light inhibit helper; D-Bus activated (`Type=dbus`), so don't enable it — the bus starts it on demand.

### `plasmoid/`

A native Plasma 6 tray applet, split into a quick popup and a Settings window so the everyday click stays uncluttered:

- **Quick popup** (click the tray icon) — just **On / Off / Schedule**. On and Off pin brightness *and* color temperature to `NORMAL_PCT`/`NORMAL_TEMP` or `DIMMED_PCT`/`DIMMED_TEMP` regardless of time of day, until you switch back to Schedule. This isn't just a shortcut: without a mode pinned, the periodic schedule timer re-applies the time-of-day target every few minutes, so a plain slider drag alone gets silently overwritten within minutes.
- **Settings…** (button in the popup, or right-click the icon → "Duskwatch Settings…") opens everything else:
  - **Brightness** / **Color temperature** sliders for live manual override — brightness applies instantly and stays put (via `set-brightness-live.sh`); color temperature live-previews via `NightLight.preview()`/`stopPreview()` the same way KDE's own Night Color KCM slider does, and reverts to the schedule when you close the window.
  - **Schedule** — Evening/Morning hours (spinboxes) each with their own Brightness and Color temperature sliders, so the schedule targets are set the same way as the live sliders above. Writes to `duskwatch.conf` via `set-config.sh`.
  - **Fade** dropdown — named presets (Instant, Smooth 20 min/1 hour, Stepped every 5/15 min) or a custom minutes field (decimals allowed, up to 12h). Smooth is a true per-second linear ramp (values creep by single units); Stepped jumps in fewer, more noticeable increments spaced a chosen number of minutes apart — see `fade-brightness.sh`'s `FADE_STYLE`.
  - **Calibrate displays…** — opens a separate window listing every connected monitor. Displays with brightness control get Floor/Ceiling sliders; dragging one live-previews on that single display (via `preview-raw.sh`, bypassing calibration so you're seeing the raw effect) and releasing commits stable `FLOOR_<key>`/`CEIL_<key>` entries to `duskwatch.conf` (keyed to the monitor's label, not its positional `displayN` slot, so calibration survives the display list reindexing). Each display also gets a **Software dimming** checkbox (via `set-software-dimming.sh`), and monitors KWin currently can't control at all are still listed with that checkbox as the way to make them controllable. Split out since it's a one-time-per-monitor setup task, not a quick toggle.
  - **Edit configuration file…** — for anything not exposed above (fade catch-up window, display allowlist, etc).

Note: the tray icon does **not** dock inside the System Tray's grouped icons. KDE's system tray only auto-shows its own hardcoded set of "known" items (volume, battery, network, etc.) — a third-party `Plasma/Applet` package gets silently dropped from that list even with `X-Plasma-NotificationArea: true` set and `Plasmoid.status` forced to `ActiveStatus`. Add it via "Add Widgets" and place it directly on a panel instead. Recommended for now — see the tray-app note below.

### `tray-app/`

A standalone Python (PyQt6) tray app with the same quick-popup/Settings split as the Plasmoid, outside of Plasma's widget system — kept in sync with it. Because it registers as a real `StatusNotifierItem` (the same protocol Discord, Bluetooth, etc. use), it docks correctly inside the System Tray's grouped icons, unlike the Plasmoid. However left-click to open it doesn't reliably work on Plasma Wayland — use right-click → "Open Duskwatch" or "Settings…" instead (see Known limitations). Pick one or the other; running both gives you two icons.

## Requirements

- KDE Plasma 6 (6.3+, for `org.kde.ScreenBrightness`), Wayland session
- `kwriteconfig6`, `kpackagetool6`, `gdbus` (part of a standard Plasma 6 install)
- PyQt6 (`python-pyqt6` on Arch) for the standalone tray app — recommended, see the System Tray note above

## Install

```
./install.sh
```

This symlinks the KWin script into `~/.local/share/kwin/scripts/`, the systemd units into `~/.config/systemd/user/`, and copies the default config to `~/.config/duskwatch/duskwatch.conf` if it doesn't already exist — so edits in this repo (or to your config) take effect without reinstalling. It does **not** enable any systemd timers/services for you — see the printed instructions to opt in.

Edit `~/.config/duskwatch/duskwatch.conf` for your schedule, brightness/color-temperature levels, and per-display calibration.

## Known limitations

- KWin's Night Color inhibitor is keyed to the caller's D-Bus connection *and* cookie (`m_inhibitors.remove(serviceName, cookie)` in KWin's `nightlightdbusinterface.cpp`), so no external process can release an inhibit held by another connection — and an inhibit taken by a KWin script belongs to KWin's own connection, which never goes away. Combined with the `callDBus()` uint32 bug above, this is how Night Color used to get stuck inhibited until logout (the helper architecture eliminates the cause). If it ever happens again anyway, there's a recovery that doesn't need a logout — Night Light is a KWin plugin, and reloading it drops the whole inhibitor table:
  ```
  gdbus call --session --dest org.kde.KWin --object-path /Plugins --method org.kde.KWin.Plugins.UnloadPlugin nightlight
  gdbus call --session --dest org.kde.KWin --object-path /Plugins --method org.kde.KWin.Plugins.LoadPlugin nightlight
  ```
- The `SetBrightness` OSD-suppression flag (`flags=1`) was found empirically, not from documentation — it could change in a future Plasma release.
- The Plasmoid does not dock inside the System Tray's grouped icons — see the note in the `plasmoid/` section above. Currently the recommended default despite that, because of the tray-app issue below.
- Real DDC/CI monitors can visibly ease into a new brightness over ~1-2s due to the monitor's own firmware, even though `SetBrightness` returns and the D-Bus `Brightness` property updates instantly (confirmed by polling it immediately after a call — no server-side ramping happens on Duskwatch's or KDE's end). Displays using KWin's software-brightness fallback apply changes instantly since there's no hardware round-trip. Nothing to fix here; it's how those monitors respond to a DDC brightness write.
- Duskwatch owns Night Color outright: scheduled color temperature pins Night Color to "Constant" mode and drives `NightTemperature` directly (see `fade-temperature.sh`), so any mode/schedule you pick in KDE's own Night Light settings will be overwritten on the next fade. Treat the Duskwatch schedule as the single source of truth for color temperature. The tray widgets' live color slider still uses `NightLight.preview()` (appropriate for interactive dragging, same as KDE's own settings slider), which as of KWin 6.7 shows a "Color Temperature Preview" OSD and auto-reverts ~15s after the last drag - it reverts to Duskwatch's scheduled value, since that's what Night Color's constant mode now holds.
- KWin applies temperature changes in internal increments of ~50K (eased over ~2s), and ignores config changes smaller than that step - so a fade can settle up to ~50K away from the exact target, and `currentTemperature` follows a slow ramp in small visible-in-logs (not on screen) quantized hops.
- `tray-app/`'s left-click-to-open doesn't reliably work under Plasma Wayland: `QSystemTrayIcon.activated` (the `Trigger` reason Qt fires on left-click) often doesn't come through KDE's Wayland StatusNotifierItem backend — a known Qt/Wayland gap, not specific to this app. Right-click → "Open Duskwatch" is the guaranteed-working path; left-click is still wired up in case it fires on your setup. Testing process: added the icon to the panel, confirmed it placed inline in the tray as a real SNI icon, then found left-click did nothing and right-click only showed "Quit" — traced to the known `activated` signal gap and added the menu action as a working fallback.
