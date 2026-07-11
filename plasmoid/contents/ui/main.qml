import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property int tempMin: 2300
    readonly property int tempMax: 6500
    readonly property string configPath: "$HOME/.config/gloaming/gloaming.conf"
    readonly property string statePath: "$HOME/.config/gloaming/state"
    readonly property string brightnessScript: "$HOME/Projects/gloaming/brightness/set-brightness-live.sh"
    readonly property string modeScript: "$HOME/Projects/gloaming/brightness/set-mode.sh"
    readonly property string configScript: "$HOME/Projects/gloaming/brightness/set-config.sh"

    property int brightnessPct: 100
    property int temperatureK: 6300
    property string mode: "schedule"

    property int eveningHour: 19
    property int morningHour: 7
    property int dimmedPct: 30
    property int normalPct: 100
    // Guards against onValueModified firing while we're setting values from
    // a config reload rather than from the user actually touching a field.
    property bool loadingSchedule: false

    property int fadeDurationSeconds: 1200
    property string fadeStyle: "smooth"
    property int fadeStepMinutes: 5
    property bool loadingFade: false
    // The ComboBox/TextField in fullRepresentation live inside a separate
    // Component scope (fullRepresentation is a Component under the hood) and
    // can't be reached by id from root-level functions - these two hold the
    // computed selection as plain data instead, and the UI binds to them.
    property int fadePresetIndex: 0
    property string customFadeMinutesText: ""
    // Longest fade a user can dial in from the custom field - past this
    // they'd want the config file anyway, and it keeps FADE_DURATION well
    // clear of anything that could make the step-count math misbehave.
    readonly property real maxCustomFadeMinutes: 720
    readonly property var fadePresets: [
        { label: i18n("Instant"), duration: 0, style: "smooth", stepMinutes: 5 },
        { label: i18n("Smooth (20 min)"), duration: 1200, style: "smooth", stepMinutes: 5 },
        { label: i18n("Smooth (1 hour)"), duration: 3600, style: "smooth", stepMinutes: 5 },
        { label: i18n("Stepped (every 5 min)"), duration: 1200, style: "stepped", stepMinutes: 5 },
        { label: i18n("Stepped (every 15 min)"), duration: 3600, style: "stepped", stepMinutes: 15 },
        { label: i18n("Custom…"), duration: -1, style: "smooth", stepMinutes: 5 }
    ]

    Plasmoid.icon: "weather-clear-night"
    // Without an explicit status, the system tray defaults custom applets to
    // Passive and hides them behind the overflow chevron - Active keeps this
    // pinned as a normal visible tray icon like Volume/Battery/Network.
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName === "cat " + root.configPath) {
                root.parseConfig(data["stdout"] || "")
            } else if (sourceName === "cat " + root.statePath) {
                root.parseState(data["stdout"] || "")
            }
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function setBrightnessLive(pct) {
        executable.exec(brightnessScript + " " + pct)
    }

    function previewTemperature(k) {
        executable.exec("gdbus call --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight --method org.kde.KWin.NightLight.preview " + k)
    }

    function stopPreview() {
        executable.exec("gdbus call --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight --method org.kde.KWin.NightLight.stopPreview")
    }

    function reloadConfig() {
        executable.exec("cat " + configPath)
        executable.exec("cat " + statePath)
    }

    function editConfig() {
        executable.exec("xdg-open " + configPath)
    }

    function setMode(newMode) {
        root.mode = newMode
        executable.exec(modeScript + " " + newMode)
    }

    function setConfigValue(key, value) {
        executable.exec(configScript + " " + key + " " + value)
    }

    function parseConfig(text) {
        function find(key, fallback) {
            var m = text.match(new RegExp("^" + key + "=(.*)$", "m"))
            return m ? m[1].trim() : fallback
        }
        loadingSchedule = true
        eveningHour = parseInt(find("EVENING_HOUR", eveningHour)) || eveningHour
        morningHour = parseInt(find("MORNING_HOUR", morningHour)) || morningHour
        dimmedPct = parseInt(find("DIMMED_PCT", dimmedPct))
        normalPct = parseInt(find("NORMAL_PCT", normalPct))
        fadeDurationSeconds = parseInt(find("FADE_DURATION", fadeDurationSeconds))
        fadeStyle = find("FADE_STYLE", fadeStyle)
        fadeStepMinutes = parseInt(find("FADE_STEP_MINUTES", fadeStepMinutes)) || fadeStepMinutes
        loadingSchedule = false
        syncFadeSelection()
    }

    function parseState(text) {
        var m = text.match(/^MODE=(.*)$/m)
        root.mode = m ? m[1].trim() : "schedule"
    }

    function syncFadeSelection() {
        // Pure data computation only - fadeCombo/customFadeField live inside
        // fullRepresentation's own Component scope and aren't reachable by
        // id from here (that was the bug: silently threw a ReferenceError,
        // caught by nothing, leaving the ComboBox stuck on its default).
        // The UI binds to fadePresetIndex/customFadeMinutesText instead.
        loadingFade = true
        for (var i = 0; i < fadePresets.length - 1; i++) {
            var p = fadePresets[i]
            if (p.duration === fadeDurationSeconds && p.style === fadeStyle) {
                fadePresetIndex = i
                loadingFade = false
                return
            }
        }
        // No preset matches - it's a custom duration (or a stepped interval
        // that doesn't match one of the two presets above).
        fadePresetIndex = fadePresets.length - 1
        customFadeMinutesText = (fadeDurationSeconds / 60).toLocaleString(Qt.locale(), 'f', 2)
        loadingFade = false
    }

    function applyFadePreset(index) {
        if (loadingFade) return
        var p = fadePresets[index]
        if (p.duration < 0) return // "Custom" - wait for the field instead
        fadeDurationSeconds = p.duration
        fadeStyle = p.style
        fadeStepMinutes = p.stepMinutes
        setConfigValue("FADE_DURATION", p.duration)
        setConfigValue("FADE_STYLE", p.style)
        setConfigValue("FADE_STEP_MINUTES", p.stepMinutes)
    }

    function applyCustomFadeMinutes(text) {
        var minutes = parseFloat(text)
        if (isNaN(minutes) || minutes < 0) minutes = 0
        if (minutes > maxCustomFadeMinutes) minutes = maxCustomFadeMinutes
        fadeDurationSeconds = Math.round(minutes * 60)
        fadeStyle = "smooth"
        setConfigValue("FADE_DURATION", fadeDurationSeconds)
        setConfigValue("FADE_STYLE", "smooth")
    }

    Component.onCompleted: reloadConfig()

    onExpandedChanged: {
        if (expanded) {
            reloadConfig()
        } else {
            stopPreview()
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: contentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
        collapseMarginsHint: true

        contentItem: ColumnLayout {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "video-display-brightness"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.Label {
                    text: i18n("Brightness")
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(brightnessSlider.value) + "%"
                    opacity: 0.7
                }
            }
            PlasmaComponents3.Slider {
                id: brightnessSlider
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.brightnessPct
                onMoved: {
                    root.brightnessPct = Math.round(value)
                    root.setBrightnessLive(root.brightnessPct)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "redshift-status-on"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.Label {
                    text: i18n("Color temperature")
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(temperatureSlider.value) + "K"
                    opacity: 0.7
                }
            }
            PlasmaComponents3.Slider {
                id: temperatureSlider
                Layout.fillWidth: true
                from: root.tempMin
                to: root.tempMax
                value: root.temperatureK
                onMoved: {
                    root.temperatureK = Math.round(value)
                    root.previewTemperature(root.temperatureK)
                }
            }

            PlasmaComponents3.Label {
                text: i18n("Color temperature reverts to the schedule when you close this; brightness stays where you set it.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            PlasmaComponents3.Label {
                text: i18n("Mode")
                font.bold: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                QQC2.ButtonGroup { id: modeGroup }

                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Day")
                    checkable: true
                    checked: root.mode === "day"
                    QQC2.ButtonGroup.group: modeGroup
                    onClicked: root.setMode("day")
                }
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Night")
                    checkable: true
                    checked: root.mode === "night"
                    QQC2.ButtonGroup.group: modeGroup
                    onClicked: root.setMode("night")
                }
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Schedule")
                    checkable: true
                    checked: root.mode === "schedule"
                    QQC2.ButtonGroup.group: modeGroup
                    onClicked: root.setMode("schedule")
                }
            }
            PlasmaComponents3.Label {
                text: root.mode === "schedule"
                    ? i18n("Follows the schedule below.")
                    : i18n("Pinned to %1 brightness until you switch back to Schedule.", root.mode === "day" ? i18n("day") : i18n("night"))
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PlasmaComponents3.Label {
                text: i18n("Schedule")
                font.bold: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label { text: i18n("Dim to") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 100
                    value: root.dimmedPct
                    onValueModified: {
                        root.dimmedPct = value
                        if (!root.loadingSchedule) root.setConfigValue("DIMMED_PCT", value)
                    }
                }
                PlasmaComponents3.Label { text: i18n("% at") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 23
                    value: root.eveningHour
                    onValueModified: {
                        root.eveningHour = value
                        if (!root.loadingSchedule) root.setConfigValue("EVENING_HOUR", value)
                    }
                }

                PlasmaComponents3.Label { text: i18n("Back to") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 100
                    value: root.normalPct
                    onValueModified: {
                        root.normalPct = value
                        if (!root.loadingSchedule) root.setConfigValue("NORMAL_PCT", value)
                    }
                }
                PlasmaComponents3.Label { text: i18n("% at") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 23
                    value: root.morningHour
                    onValueModified: {
                        root.morningHour = value
                        if (!root.loadingSchedule) root.setConfigValue("MORNING_HOUR", value)
                    }
                }
            }

            PlasmaComponents3.Label {
                text: i18n("Fade")
                font.bold: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
            PlasmaComponents3.ComboBox {
                id: fadeCombo
                Layout.fillWidth: true
                textRole: "label"
                model: root.fadePresets
                currentIndex: root.fadePresetIndex
                onActivated: (index) => root.applyFadePreset(index)
            }
            RowLayout {
                Layout.fillWidth: true
                visible: fadeCombo.currentIndex === root.fadePresets.length - 1
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: customFadeField
                    Layout.fillWidth: true
                    placeholderText: i18n("Minutes, e.g. 0.5")
                    text: root.customFadeMinutesText
                    validator: DoubleValidator {
                        bottom: 0
                        top: root.maxCustomFadeMinutes
                        decimals: 2
                        notation: DoubleValidator.StandardNotation
                    }
                    onEditingFinished: root.applyCustomFadeMinutes(text)
                }
                PlasmaComponents3.Label {
                    text: i18n("min (up to %1h)", Math.round(root.maxCustomFadeMinutes / 60))
                    opacity: 0.6
                }
            }
        }

        footer: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                PlasmaComponents3.ToolButton {
                    text: i18n("Calibrate displays…")
                    icon.name: "configure"
                    onClicked: {
                        calibrationDialog.reload()
                        calibrationDialog.show()
                    }
                }
                PlasmaComponents3.ToolButton {
                    text: i18n("Edit configuration file…")
                    icon.name: "document-edit"
                    onClicked: root.editConfig()
                }
                Item { Layout.fillWidth: true }
            }
        }

        CalibrationDialog {
            id: calibrationDialog
            visible: false
        }
    }
}
