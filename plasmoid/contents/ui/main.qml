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

    readonly property string statePath: "$HOME/.config/duskwatch/state"
    readonly property string modeScript: "$HOME/Projects/duskwatch/brightness/set-mode.sh"

    property string mode: "schedule"

    Plasmoid.icon: "weather-clear-night"
    // Without an explicit status, the system tray defaults custom applets to
    // Passive and hides them behind the overflow chevron - Active keeps this
    // pinned as a normal visible tray icon like Volume/Battery/Network.
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Duskwatch Settings…")
            icon.name: "configure"
            onTriggered: checked => settingsDialog.openDialog()
        }
    ]

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName === "cat " + root.statePath) {
                root.parseState(data["stdout"] || "")
            }
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function reloadState() {
        executable.exec("cat " + statePath)
    }

    function setMode(newMode) {
        root.mode = newMode
        executable.exec(modeScript + " " + newMode)
    }

    function parseState(text) {
        var m = text.match(/^MODE=(.*)$/m)
        root.mode = m ? m[1].trim() : "schedule"
    }

    Component.onCompleted: reloadState()

    onExpandedChanged: if (expanded) reloadState()

    SettingsDialog {
        id: settingsDialog
        visible: false
        function openDialog() {
            reloadFromDisk()
            show()
            raise()
            requestActivate()
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
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
                spacing: 0

                QQC2.ButtonGroup { id: modeGroup }

                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("On")
                    checkable: true
                    checked: root.mode === "day"
                    QQC2.ButtonGroup.group: modeGroup
                    onClicked: root.setMode("day")
                }
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Off")
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
                    ? i18n("Following the schedule.")
                    : root.mode === "day"
                        ? i18n("On - full brightness until you switch back to Schedule.")
                        : i18n("Off - dimmed until you switch back to Schedule.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        footer: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                PlasmaComponents3.ToolButton {
                    text: i18n("Settings…")
                    icon.name: "configure"
                    onClicked: settingsDialog.openDialog()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
