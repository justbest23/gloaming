#!/usr/bin/env python3
"""Standalone tray app for manual Night Color / brightness override.

Mirrors the Plasmoid's interaction model: brightness changes apply live and
persist, color temperature previews live via KWin's NightLight.preview() and
reverts to the schedule when the popup closes.
"""
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QCursor, QIcon
from PyQt6.QtWidgets import (
    QApplication,
    QLabel,
    QMenu,
    QSlider,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

BRIGHTNESS_SCRIPT = Path(__file__).resolve().parent.parent / "brightness" / "set-brightness-live.sh"
TEMP_MIN, TEMP_MAX, TEMP_DEFAULT = 2300, 6500, 6300


def set_brightness_live(pct: int) -> None:
    subprocess.Popen([str(BRIGHTNESS_SCRIPT), str(pct)])


def preview_temperature(kelvin: int) -> None:
    subprocess.Popen([
        "gdbus", "call", "--session", "--dest", "org.kde.KWin",
        "--object-path", "/org/kde/KWin/NightLight",
        "--method", "org.kde.KWin.NightLight.preview", str(kelvin),
    ])


def stop_preview() -> None:
    subprocess.Popen([
        "gdbus", "call", "--session", "--dest", "org.kde.KWin",
        "--object-path", "/org/kde/KWin/NightLight",
        "--method", "org.kde.KWin.NightLight.stopPreview",
    ])


class GloamingPopup(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowFlag(Qt.WindowType.Popup)
        self.setWindowTitle("Gloaming")

        layout = QVBoxLayout(self)

        layout.addWidget(QLabel("Brightness"))
        self.brightness_slider = QSlider(Qt.Orientation.Horizontal)
        self.brightness_slider.setRange(0, 100)
        self.brightness_slider.setValue(100)
        self.brightness_slider.valueChanged.connect(set_brightness_live)
        layout.addWidget(self.brightness_slider)

        layout.addWidget(QLabel("Color temperature"))
        self.temp_slider = QSlider(Qt.Orientation.Horizontal)
        self.temp_slider.setRange(TEMP_MIN, TEMP_MAX)
        self.temp_slider.setValue(TEMP_DEFAULT)
        self.temp_slider.valueChanged.connect(preview_temperature)
        layout.addWidget(self.temp_slider)

        note = QLabel(
            "Color temperature reverts to the schedule when you close this;\n"
            "brightness stays where you set it."
        )
        note.setWordWrap(True)
        layout.addWidget(note)

    def hideEvent(self, event) -> None:
        stop_preview()
        super().hideEvent(event)


def main() -> None:
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    tray = QSystemTrayIcon(QIcon.fromTheme("weather-clear-night"))
    tray.setToolTip("Gloaming")

    popup = GloamingPopup()

    def toggle_popup() -> None:
        if popup.isVisible():
            popup.hide()
            return
        pos = QCursor.pos()
        popup.move(pos.x(), pos.y() - popup.sizeHint().height())
        popup.show()

    # Left-click (ActivationReason.Trigger) is the normal way to open this,
    # but QSystemTrayIcon.activated doesn't reliably fire through KDE's
    # Wayland StatusNotifierItem backend - a known Qt/Wayland gap, not
    # specific to this app. The "Open Gloaming" menu action is the
    # guaranteed-working fallback via right-click; left-click still wired up
    # in case it does fire on a given setup.
    def on_activated(reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            toggle_popup()

    tray.activated.connect(on_activated)

    menu = QMenu()
    menu.addAction("Open Gloaming").triggered.connect(toggle_popup)
    menu.addSeparator()
    menu.addAction("Quit").triggered.connect(app.quit)
    tray.setContextMenu(menu)

    tray.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
