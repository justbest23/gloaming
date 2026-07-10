#!/bin/bash
# install.sh - installs the KWin script and systemd units by symlinking them
# into place, so future edits in this repo take effect without reinstalling.
set -euo pipefail
cd "$(dirname "$0")"
REPO=$(pwd)

mkdir -p ~/.local/share/kwin/scripts ~/.config/systemd/user ~/.config/gloaming
[[ -f ~/.config/gloaming/gloaming.conf ]] || cp config/gloaming.conf.default ~/.config/gloaming/gloaming.conf

rm -rf ~/.local/share/kwin/scripts/nightcolor-fullscreen-inhibit
ln -sf "$REPO/kwin-scripts/nightcolor-fullscreen-inhibit" ~/.local/share/kwin/scripts/nightcolor-fullscreen-inhibit
kwriteconfig6 --file kwinrc --group Plugins --key nightcolor-fullscreen-inhibitEnabled true
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure

for unit in systemd/*.service systemd/*.timer; do
    ln -sf "$REPO/$unit" ~/.config/systemd/user/"$(basename "$unit")"
done
systemctl --user daemon-reload

mkdir -p ~/.local/share/plasma/plasmoids
rm -rf ~/.local/share/plasma/plasmoids/org.gloaming.trayapplet
ln -sf "$REPO/plasmoid" ~/.local/share/plasma/plasmoids/org.gloaming.trayapplet

chmod +x brightness/*.sh

echo "Installed. Edit ~/.config/gloaming/gloaming.conf to set your schedule,"
echo "brightness levels, and per-display calibration."
echo "Then enable the timers/services you want, e.g.:"
echo "  systemctl --user enable --now gloaming-brightness-schedule.timer"
echo "  systemctl --user enable --now gloaming-fullscreen-brightness-watch.service"
echo "The Gloaming tray widget is installed - add it via your panel's"
echo "'Add Widgets' dialog, or the system tray's '+' configure button."
