import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: dialog
    title: i18n("Gloaming - Display Calibration")
    width: Kirigami.Units.gridUnit * 26
    height: Kirigami.Units.gridUnit * 20

    readonly property string listScript: "$HOME/Projects/gloaming/brightness/list-displays.sh"
    readonly property string previewScript: "$HOME/Projects/gloaming/brightness/preview-raw.sh"
    readonly property string configScript: "$HOME/Projects/gloaming/brightness/set-config.sh"

    property var displays: []

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName === dialog.listScript) {
                dialog.parseDisplays(data["stdout"] || "")
            }
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function reload() {
        executable.exec(listScript)
    }

    function parseDisplays(text) {
        var rows = []
        text.split("\n").forEach(line => {
            if (!line.trim()) return
            var parts = line.split("|")
            if (parts.length !== 4) return
            rows.push({ id: parts[0], label: parts[1], floor: parseInt(parts[2]), ceil: parseInt(parts[3]) })
        })
        displays = rows
    }

    function preview(displayId, pct) {
        executable.exec(previewScript + " " + displayId + " " + pct)
    }

    function setFloor(displayId, value) {
        executable.exec(configScript + " FLOOR_" + displayId + " " + value)
    }

    function setCeil(displayId, value) {
        executable.exec(configScript + " CEIL_" + displayId + " " + value)
    }

    Component.onCompleted: reload()

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: i18n("Display Calibration")

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: i18n("Monitors vary a lot in perceived brightness at the same raw percentage. Drag Floor/Ceiling for a display to preview it live on that monitor, then leave it where it visually matches the others.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.7
            }

            Repeater {
                model: dialog.displays
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Label {
                        text: modelData.label
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label { text: i18n("Floor") }
                        PlasmaComponents3.Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: modelData.floor
                            onMoved: dialog.preview(modelData.id, Math.round(value))
                            onPressedChanged: if (!pressed) dialog.setFloor(modelData.id, Math.round(value))
                        }
                        PlasmaComponents3.Label {
                            text: modelData.floor + "%"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label { text: i18n("Ceiling") }
                        PlasmaComponents3.Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: modelData.ceil
                            onMoved: dialog.preview(modelData.id, Math.round(value))
                            onPressedChanged: if (!pressed) dialog.setCeil(modelData.id, Math.round(value))
                        }
                        PlasmaComponents3.Label {
                            text: modelData.ceil + "%"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        }
                    }
                    Kirigami.Separator {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                    }
                }
            }
        }
    }
}
