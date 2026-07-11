import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: dialog
    title: i18n("Duskwatch Settings")
    width: Kirigami.Units.gridUnit * 22
    height: Kirigami.Units.gridUnit * 24

    readonly property int tempMin: 2300
    readonly property int tempMax: 6500
    readonly property string configPath: "$HOME/.config/duskwatch/duskwatch.conf"
    readonly property string brightnessScript: "$HOME/Projects/duskwatch/brightness/set-brightness-live.sh"
    readonly property string configScript: "$HOME/Projects/duskwatch/brightness/set-config.sh"

    property int brightnessPct: 100
    property int temperatureK: 6300

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
    property int fadePresetIndex: 0
    property string customFadeMinutesText: ""
    readonly property real maxCustomFadeMinutes: 720
    readonly property var fadePresets: [
        { label: i18n("Instant"), duration: 0, style: "smooth", stepMinutes: 5 },
        { label: i18n("Smooth (20 min)"), duration: 1200, style: "smooth", stepMinutes: 5 },
        { label: i18n("Smooth (1 hour)"), duration: 3600, style: "smooth", stepMinutes: 5 },
        { label: i18n("Stepped (every 5 min)"), duration: 1200, style: "stepped", stepMinutes: 5 },
        { label: i18n("Stepped (every 15 min)"), duration: 3600, style: "stepped", stepMinutes: 15 },
        { label: i18n("Custom…"), duration: -1, style: "smooth", stepMinutes: 5 }
    ]

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName === "cat " + dialog.configPath) {
                dialog.parseConfig(data["stdout"] || "")
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

    function reloadFromDisk() {
        executable.exec("cat " + configPath)
    }

    function editConfig() {
        executable.exec("xdg-open " + configPath)
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

    function syncFadeSelection() {
        loadingFade = true
        for (var i = 0; i < fadePresets.length - 1; i++) {
            var p = fadePresets[i]
            if (p.duration === fadeDurationSeconds && p.style === fadeStyle) {
                fadePresetIndex = i
                loadingFade = false
                return
            }
        }
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

    onVisibleChanged: if (!visible) stopPreview()

    CalibrationDialog {
        id: calibrationDialog
        visible: false
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: i18n("Duskwatch Settings")

        ColumnLayout {
            width: parent.width
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
                value: dialog.brightnessPct
                onMoved: {
                    dialog.brightnessPct = Math.round(value)
                    dialog.setBrightnessLive(dialog.brightnessPct)
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
                from: dialog.tempMin
                to: dialog.tempMax
                value: dialog.temperatureK
                onMoved: {
                    dialog.temperatureK = Math.round(value)
                    dialog.previewTemperature(dialog.temperatureK)
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
                    value: dialog.dimmedPct
                    onValueModified: {
                        dialog.dimmedPct = value
                        if (!dialog.loadingSchedule) dialog.setConfigValue("DIMMED_PCT", value)
                    }
                }
                PlasmaComponents3.Label { text: i18n("% at") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 23
                    value: dialog.eveningHour
                    onValueModified: {
                        dialog.eveningHour = value
                        if (!dialog.loadingSchedule) dialog.setConfigValue("EVENING_HOUR", value)
                    }
                }

                PlasmaComponents3.Label { text: i18n("Back to") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 100
                    value: dialog.normalPct
                    onValueModified: {
                        dialog.normalPct = value
                        if (!dialog.loadingSchedule) dialog.setConfigValue("NORMAL_PCT", value)
                    }
                }
                PlasmaComponents3.Label { text: i18n("% at") }
                PlasmaComponents3.SpinBox {
                    from: 0; to: 23
                    value: dialog.morningHour
                    onValueModified: {
                        dialog.morningHour = value
                        if (!dialog.loadingSchedule) dialog.setConfigValue("MORNING_HOUR", value)
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
                model: dialog.fadePresets
                currentIndex: dialog.fadePresetIndex
                onActivated: (index) => dialog.applyFadePreset(index)
            }
            RowLayout {
                Layout.fillWidth: true
                visible: fadeCombo.currentIndex === dialog.fadePresets.length - 1
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    Layout.fillWidth: true
                    placeholderText: i18n("Minutes, e.g. 0.5")
                    text: dialog.customFadeMinutesText
                    validator: DoubleValidator {
                        bottom: 0
                        top: dialog.maxCustomFadeMinutes
                        decimals: 2
                        notation: DoubleValidator.StandardNotation
                    }
                    onEditingFinished: dialog.applyCustomFadeMinutes(text)
                }
                PlasmaComponents3.Label {
                    text: i18n("min (up to %1h)", Math.round(dialog.maxCustomFadeMinutes / 60))
                    opacity: 0.6
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                PlasmaComponents3.Button {
                    text: i18n("Calibrate displays…")
                    icon.name: "configure"
                    onClicked: {
                        calibrationDialog.reload()
                        calibrationDialog.show()
                    }
                }
                PlasmaComponents3.Button {
                    text: i18n("Edit configuration file…")
                    icon.name: "document-edit"
                    onClicked: dialog.editConfig()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
