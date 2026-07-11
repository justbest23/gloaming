#!/usr/bin/env python3
"""Standalone tray app for manual Night Color / brightness override.

Mirrors the Plasmoid's interaction model: brightness changes apply live and
persist, color temperature previews live via KWin's NightLight.preview() and
reverts to the schedule when the popup closes. Also mirrors the Plasmoid's
Day/Night/Schedule mode switch and editable schedule fields.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QCursor, QIcon
from PyQt6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QComboBox,
    QDialog,
    QDoubleSpinBox,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QMenu,
    QPushButton,
    QScrollArea,
    QSlider,
    QSpinBox,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
BRIGHTNESS_SCRIPT = REPO_ROOT / "brightness" / "set-brightness-live.sh"
MODE_SCRIPT = REPO_ROOT / "brightness" / "set-mode.sh"
CONFIG_SCRIPT = REPO_ROOT / "brightness" / "set-config.sh"
LIST_DISPLAYS_SCRIPT = REPO_ROOT / "brightness" / "list-displays.sh"
PREVIEW_RAW_SCRIPT = REPO_ROOT / "brightness" / "preview-raw.sh"

XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
CONFIG_FILE = XDG_CONFIG_HOME / "gloaming" / "gloaming.conf"
STATE_FILE = XDG_CONFIG_HOME / "gloaming" / "state"

TEMP_MIN, TEMP_MAX, TEMP_DEFAULT = 2300, 6500, 6300

# (label, duration_seconds, style, step_minutes) - mirrors plasmoid/contents/ui/main.qml's
# fadePresets. duration=None marks the "Custom" entry, always last.
FADE_PRESETS = [
    ("Instant", 0, "smooth", 5),
    ("Smooth (20 min)", 1200, "smooth", 5),
    ("Smooth (1 hour)", 3600, "smooth", 5),
    ("Stepped (every 5 min)", 1200, "stepped", 5),
    ("Stepped (every 15 min)", 3600, "stepped", 15),
    ("Custom…", None, "smooth", 5),
]
# Longest fade a user can dial in from the custom field - past this they'd
# want the config file anyway, and it keeps FADE_DURATION well clear of
# anything that could make fade-brightness.sh's step-count math misbehave.
MAX_CUSTOM_FADE_MINUTES = 720


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


def set_mode(mode: str) -> None:
    subprocess.Popen([str(MODE_SCRIPT), mode])


def set_config_value(key: str, value: int) -> None:
    subprocess.Popen([str(CONFIG_SCRIPT), key, str(value)])


def edit_config() -> None:
    subprocess.Popen(["xdg-open", str(CONFIG_FILE)])


def preview_raw(display_id: str, pct: int) -> None:
    subprocess.Popen([str(PREVIEW_RAW_SCRIPT), display_id, str(pct)])


def list_displays() -> list[tuple[str, str, int, int]]:
    try:
        out = subprocess.run(
            [str(LIST_DISPLAYS_SCRIPT)], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    displays = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) != 4:
            continue
        display_id, label, floor, ceil = parts
        displays.append((display_id, label, int(floor), int(ceil)))
    return displays


def read_config() -> dict[str, str]:
    try:
        text = CONFIG_FILE.read_text()
    except OSError:
        return {}
    return dict(re.findall(r"^([A-Z_][A-Za-z0-9_]*)=(.*)$", text, re.MULTILINE))


def read_mode() -> str:
    try:
        text = STATE_FILE.read_text()
    except OSError:
        return "schedule"
    m = re.search(r"^MODE=(.*)$", text, re.MULTILINE)
    return m.group(1).strip() if m else "schedule"


class GloamingPopup(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowFlag(Qt.WindowType.Popup)
        self.setWindowTitle("Gloaming")
        self._loading_schedule = False

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

        layout.addWidget(_separator())

        layout.addWidget(_bold(QLabel("Mode")))
        mode_row = QHBoxLayout()
        self.mode_buttons: dict[str, QPushButton] = {}
        self.mode_group = QButtonGroup(self)
        for mode in ("day", "night", "schedule"):
            btn = QPushButton(mode.capitalize())
            btn.setCheckable(True)
            btn.clicked.connect(lambda _checked, m=mode: self._on_mode_clicked(m))
            self.mode_group.addButton(btn)
            self.mode_buttons[mode] = btn
            mode_row.addWidget(btn)
        layout.addLayout(mode_row)

        self.mode_note = QLabel()
        self.mode_note.setWordWrap(True)
        layout.addWidget(self.mode_note)

        layout.addWidget(_bold(QLabel("Schedule")))
        grid = QGridLayout()
        self.dimmed_spin = QSpinBox()
        self.dimmed_spin.setRange(0, 100)
        self.dimmed_spin.valueChanged.connect(lambda v: self._on_schedule_changed("DIMMED_PCT", v))
        self.evening_spin = QSpinBox()
        self.evening_spin.setRange(0, 23)
        self.evening_spin.valueChanged.connect(lambda v: self._on_schedule_changed("EVENING_HOUR", v))
        self.normal_spin = QSpinBox()
        self.normal_spin.setRange(0, 100)
        self.normal_spin.valueChanged.connect(lambda v: self._on_schedule_changed("NORMAL_PCT", v))
        self.morning_spin = QSpinBox()
        self.morning_spin.setRange(0, 23)
        self.morning_spin.valueChanged.connect(lambda v: self._on_schedule_changed("MORNING_HOUR", v))

        grid.addWidget(QLabel("Dim to"), 0, 0)
        grid.addWidget(self.dimmed_spin, 0, 1)
        grid.addWidget(QLabel("% at"), 0, 2)
        grid.addWidget(self.evening_spin, 0, 3)
        grid.addWidget(QLabel("Back to"), 1, 0)
        grid.addWidget(self.normal_spin, 1, 1)
        grid.addWidget(QLabel("% at"), 1, 2)
        grid.addWidget(self.morning_spin, 1, 3)
        layout.addLayout(grid)

        layout.addWidget(_bold(QLabel("Fade")))
        self.fade_combo = QComboBox()
        self.fade_combo.addItems([p[0] for p in FADE_PRESETS])
        self.fade_combo.activated.connect(self._on_fade_activated)
        layout.addWidget(self.fade_combo)

        custom_row = QHBoxLayout()
        self.custom_fade_spin = QDoubleSpinBox()
        self.custom_fade_spin.setRange(0, MAX_CUSTOM_FADE_MINUTES)
        self.custom_fade_spin.setDecimals(2)
        self.custom_fade_spin.setSuffix(" min")
        self.custom_fade_spin.editingFinished.connect(self._on_custom_fade_changed)
        self.custom_fade_row = custom_row
        custom_row.addWidget(self.custom_fade_spin)
        custom_row.addWidget(QLabel(f"(up to {MAX_CUSTOM_FADE_MINUTES // 60}h)"))
        layout.addLayout(custom_row)
        self._set_custom_row_visible(False)

        layout.addWidget(_separator())

        edit_row = QHBoxLayout()
        calibrate_btn = QPushButton("Calibrate displays…")
        calibrate_btn.setFlat(True)
        calibrate_btn.clicked.connect(self._open_calibration)
        edit_row.addWidget(calibrate_btn)
        edit_btn = QPushButton("Edit configuration file…")
        edit_btn.setFlat(True)
        edit_btn.clicked.connect(edit_config)
        edit_row.addWidget(edit_btn)
        edit_row.addStretch()
        layout.addLayout(edit_row)

        self._calibration_dialog: CalibrationDialog | None = None

    def _open_calibration(self) -> None:
        if self._calibration_dialog is None:
            self._calibration_dialog = CalibrationDialog(self)
        self._calibration_dialog.reload_from_disk()
        self._calibration_dialog.show()
        self._calibration_dialog.raise_()
        self._calibration_dialog.activateWindow()

    def _set_custom_row_visible(self, visible: bool) -> None:
        self.custom_fade_spin.setVisible(visible)
        for i in range(self.custom_fade_row.count()):
            widget = self.custom_fade_row.itemAt(i).widget()
            if widget:
                widget.setVisible(visible)

    def _on_fade_activated(self, index: int) -> None:
        _label, duration, style, step_minutes = FADE_PRESETS[index]
        self._set_custom_row_visible(duration is None)
        if duration is None:
            return  # "Custom" - wait for the field instead
        set_config_value("FADE_DURATION", duration)
        set_config_value("FADE_STYLE", style)
        set_config_value("FADE_STEP_MINUTES", step_minutes)

    def _on_custom_fade_changed(self) -> None:
        duration = round(self.custom_fade_spin.value() * 60)
        set_config_value("FADE_DURATION", duration)
        set_config_value("FADE_STYLE", "smooth")

    def _sync_fade_selection(self, duration: int, style: str) -> None:
        for i, (_label, preset_duration, preset_style, _step) in enumerate(FADE_PRESETS[:-1]):
            if preset_duration == duration and preset_style == style:
                self.fade_combo.setCurrentIndex(i)
                self._set_custom_row_visible(False)
                return
        self.fade_combo.setCurrentIndex(len(FADE_PRESETS) - 1)
        self.custom_fade_spin.setValue(duration / 60)
        self._set_custom_row_visible(True)

    def _on_mode_clicked(self, mode: str) -> None:
        self._set_mode_ui(mode)
        set_mode(mode)

    def _set_mode_ui(self, mode: str) -> None:
        self.mode_buttons.get(mode, self.mode_buttons["schedule"]).setChecked(True)
        self.mode_note.setText(
            "Follows the schedule below."
            if mode == "schedule"
            else f"Pinned to {mode} brightness until you switch back to Schedule."
        )

    def _on_schedule_changed(self, key: str, value: int) -> None:
        if not self._loading_schedule:
            set_config_value(key, value)

    def reload_from_disk(self) -> None:
        config = read_config()
        self._loading_schedule = True
        if "DIMMED_PCT" in config:
            self.dimmed_spin.setValue(int(config["DIMMED_PCT"]))
        if "EVENING_HOUR" in config:
            self.evening_spin.setValue(int(config["EVENING_HOUR"]))
        if "NORMAL_PCT" in config:
            self.normal_spin.setValue(int(config["NORMAL_PCT"]))
        if "MORNING_HOUR" in config:
            self.morning_spin.setValue(int(config["MORNING_HOUR"]))
        self._loading_schedule = False
        self._set_mode_ui(read_mode())
        self._sync_fade_selection(
            int(config.get("FADE_DURATION", 1200)),
            config.get("FADE_STYLE", "smooth"),
        )

    def showEvent(self, event) -> None:
        self.reload_from_disk()
        super().showEvent(event)

    def hideEvent(self, event) -> None:
        stop_preview()
        super().hideEvent(event)


class CalibrationDialog(QDialog):
    """Per-display Floor/Ceiling calibration, kept separate from the main
    popup since it's a one-time-per-monitor setup task, not a quick toggle.
    Dragging a slider previews live on that one display via preview-raw.sh;
    releasing it commits FLOOR_/CEIL_<display> to gloaming.conf.
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Gloaming - Display Calibration")
        self.resize(480, 400)

        outer = QVBoxLayout(self)
        intro = QLabel(
            "Monitors vary a lot in perceived brightness at the same raw "
            "percentage. Drag Floor/Ceiling for a display to preview it live "
            "on that monitor, then leave it where it visually matches the "
            "others."
        )
        intro.setWordWrap(True)
        outer.addWidget(intro)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        outer.addWidget(scroll)

        self._rows_container = QWidget()
        self._rows_layout = QVBoxLayout(self._rows_container)
        scroll.setWidget(self._rows_container)

    def reload_from_disk(self) -> None:
        while self._rows_layout.count():
            item = self._rows_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        for display_id, label, floor, ceil in list_displays():
            self._rows_layout.addWidget(self._make_row(display_id, label, floor, ceil))
        self._rows_layout.addStretch()

    def _make_row(self, display_id: str, label: str, floor: int, ceil: int) -> QWidget:
        row = QWidget()
        layout = QVBoxLayout(row)
        layout.addWidget(_bold(QLabel(label)))

        floor_row = QHBoxLayout()
        floor_row.addWidget(QLabel("Floor"))
        floor_slider = QSlider(Qt.Orientation.Horizontal)
        floor_slider.setRange(0, 100)
        floor_slider.setValue(floor)
        floor_label = QLabel(f"{floor}%")
        floor_slider.valueChanged.connect(lambda v: (preview_raw(display_id, v), floor_label.setText(f"{v}%")))
        floor_slider.sliderReleased.connect(lambda: set_config_value(f"FLOOR_{display_id}", floor_slider.value()))
        floor_row.addWidget(floor_slider)
        floor_row.addWidget(floor_label)
        layout.addLayout(floor_row)

        ceil_row = QHBoxLayout()
        ceil_row.addWidget(QLabel("Ceiling"))
        ceil_slider = QSlider(Qt.Orientation.Horizontal)
        ceil_slider.setRange(0, 100)
        ceil_slider.setValue(ceil)
        ceil_label = QLabel(f"{ceil}%")
        ceil_slider.valueChanged.connect(lambda v: (preview_raw(display_id, v), ceil_label.setText(f"{v}%")))
        ceil_slider.sliderReleased.connect(lambda: set_config_value(f"CEIL_{display_id}", ceil_slider.value()))
        ceil_row.addWidget(ceil_slider)
        ceil_row.addWidget(ceil_label)
        layout.addLayout(ceil_row)

        layout.addWidget(_separator())
        return row


def _bold(label: QLabel) -> QLabel:
    font = label.font()
    font.setBold(True)
    label.setFont(font)
    return label


def _separator() -> QWidget:
    from PyQt6.QtWidgets import QFrame
    line = QFrame()
    line.setFrameShape(QFrame.Shape.HLine)
    line.setFrameShadow(QFrame.Shadow.Sunken)
    return line


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
