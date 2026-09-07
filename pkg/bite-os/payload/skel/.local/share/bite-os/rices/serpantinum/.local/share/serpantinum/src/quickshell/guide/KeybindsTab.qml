// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Edits the keybinds in ~/.config/hypr/settings.json via
//  scripts/keybind-edit.sh. settings.json is the source of truth:
//  settings_watcher.sh regenerates config/keybindings.conf and reloads
//  hyprland, so nothing here ever touches a .conf directly.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: kbRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    readonly property string helper: "~/.config/hypr/scripts/keybind-edit.sh"
    property var binds: []
    property string status: ""
    property bool busy: false
    property string filter: ""

    function refresh() { listProc.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    function runEdit(desc, argstr) {
        if (kbRoot.busy) return;
        kbRoot.busy = true;
        kbRoot.status = desc + " …";
        editProc.desc = desc;
        editProc.command = ["bash", "-c", kbRoot.helper + " " + argstr];
        editProc.running = true;
    }

    Process {
        id: listProc
        running: false
        command: ["bash", "-c", kbRoot.helper + " list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                if (!out) return;
                try { kbRoot.binds = JSON.parse(out.trim()); }
                catch (e) { kbRoot.status = "could not read keybinds"; }
            }
        }
    }

    Process {
        id: editProc
        running: false
        property string desc: ""
        stdout: StdioCollector {
            onStreamFinished: {
                void this.text;
                kbRoot.busy = false;
                kbRoot.status = editProc.desc + " — saved";
                kbRoot.refresh();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: rootObj.s(10)

        Text {
            text: "Keybinds"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: rootObj.s(22)
            color: ThemeBackend.text
        }

        Text {
            text: "Edits ~/.config/hypr/settings.json — hyprland reloads itself. Every change is backed up first."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
            color: ThemeBackend.subtext0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: rootObj.s(8)

            Input {
                Layout.fillWidth: true
                implicitHeight: rootObj.s(32)
                text: kbRoot.filter
                placeholderText: "filter by key or command…"
                baseColor: ThemeBackend.surface0
                accentColor: ThemeBackend.green
                textColor: ThemeBackend.text
                subTextColor: ThemeBackend.subtext0
                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                cornerRadius: ThemeBackend.borderRadius
                fontPixelSize: rootObj.s(11)
                onTextEdited: function(t) { kbRoot.filter = t; }
            }

            Text {
                text: kbRoot.status
                visible: kbRoot.status !== ""
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.peach
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: rootObj.s(6)

                Repeater {
                    model: kbRoot.binds

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool shown: kbRoot.filter === ""
                            || (modelData.key + " " + modelData.mods + " " + modelData.command)
                               .toLowerCase().indexOf(kbRoot.filter.toLowerCase()) !== -1

                        Layout.fillWidth: true
                        visible: shown
                        implicitHeight: shown ? row.implicitHeight + rootObj.s(12) : 0
                        radius: ThemeBackend.clampedBorderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.55)

                        RowLayout {
                            id: row
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: rootObj.s(8)
                            spacing: rootObj.s(6)

                            Input {
                                implicitWidth: rootObj.s(150)
                                implicitHeight: rootObj.s(30)
                                text: modelData.mods
                                placeholderText: "$mainMod SHIFT"
                                baseColor: ThemeBackend.surface1
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: rootObj.s(10)
                                onAccepted: function(t) {
                                    kbRoot.runEdit("Updated " + t + " " + modelData.key,
                                        "set " + modelData.i + " " + kbRoot.shq(t) + " "
                                        + kbRoot.shq(modelData.key) + " "
                                        + kbRoot.shq(modelData.dispatcher) + " "
                                        + kbRoot.shq(modelData.command));
                                }
                            }

                            Input {
                                implicitWidth: rootObj.s(80)
                                implicitHeight: rootObj.s(30)
                                text: modelData.key
                                placeholderText: "key"
                                baseColor: ThemeBackend.surface1
                                accentColor: ThemeBackend.green
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: rootObj.s(10)
                                onAccepted: function(t) {
                                    kbRoot.runEdit("Updated " + modelData.mods + " " + t,
                                        "set " + modelData.i + " " + kbRoot.shq(modelData.mods) + " "
                                        + kbRoot.shq(t) + " "
                                        + kbRoot.shq(modelData.dispatcher) + " "
                                        + kbRoot.shq(modelData.command));
                                }
                            }

                            Input {
                                Layout.fillWidth: true
                                implicitHeight: rootObj.s(30)
                                text: modelData.command
                                placeholderText: "command"
                                baseColor: ThemeBackend.surface1
                                accentColor: ThemeBackend.blue
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: rootObj.s(10)
                                onAccepted: function(t) {
                                    kbRoot.runEdit("Updated " + modelData.mods + " " + modelData.key,
                                        "set " + modelData.i + " " + kbRoot.shq(modelData.mods) + " "
                                        + kbRoot.shq(modelData.key) + " "
                                        + kbRoot.shq(modelData.dispatcher) + " "
                                        + kbRoot.shq(t));
                                }
                            }

                            Text {
                                text: modelData.dispatcher
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(9)
                                color: ThemeBackend.subtext0
                            }

                            ClickButton {
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰩹"
                                iconFontSize: rootObj.s(13)
                                accentColor: ThemeBackend.red
                                textColor: ThemeBackend.red
                                onClicked: kbRoot.runEdit("Deleted " + modelData.mods + " " + modelData.key,
                                                          "delete " + modelData.i)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: rootObj.s(8)

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(34)
                buttonText: "Add keybind"
                buttonIcon: "󰐕"
                accentColor: ThemeBackend.green
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                textColor: ThemeBackend.green
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(11)
                iconFontSize: rootObj.s(14)
                fillDuration: 700
                onTriggered: kbRoot.runEdit("Added keybind",
                    "add " + kbRoot.shq("$mainMod") + " " + kbRoot.shq("F1") + " "
                    + kbRoot.shq("exec") + " " + kbRoot.shq("notify-send 'new bind'"))
            }

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(34)
                buttonText: "Undo last change"
                buttonIcon: "󰕌"
                accentColor: ThemeBackend.peach
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                textColor: ThemeBackend.peach
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(11)
                iconFontSize: rootObj.s(14)
                fillDuration: 1200
                onTriggered: kbRoot.runEdit("Restored backup", "restore")
            }
        }
    }
}
