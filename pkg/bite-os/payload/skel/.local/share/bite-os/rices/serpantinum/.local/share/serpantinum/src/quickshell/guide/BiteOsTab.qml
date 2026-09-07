// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Rice vault controls: save the current look/keybinds into
//  the vault, roll back, or swap to another rice.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: biteTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property string activeRice: "…"
    property string activeShell: "…"
    property string statusLine: ""
    property bool busy: false

    function refresh() { riceStatusProc.running = true; }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Process {
        id: riceStatusProc
        running: false
        command: ["bash", "-c",
            "printf '%s\\n%s\\n' \"$(cat ~/.local/share/bite-os/rices/.active 2>/dev/null || echo unknown)\" \"$(cat ~/.local/state/bite-os/active-shell 2>/dev/null || echo unknown)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                if (!out) return;
                let parts = out.trim().split("\n");
                biteTabRoot.activeRice = (parts[0] || "unknown").trim();
                biteTabRoot.activeShell = (parts[1] || "unknown").trim();
            }
        }
    }

    Process {
        id: actionProc
        running: false
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                void this.text;
                biteTabRoot.busy = false;
                biteTabRoot.statusLine = actionProc.label + " — done";
                biteTabRoot.refresh();
            }
        }
    }

    function runAction(label, cmd) {
        if (biteTabRoot.busy) return;
        biteTabRoot.busy = true;
        biteTabRoot.statusLine = label + " …";
        actionProc.label = label;
        actionProc.command = ["bash", "-c", cmd];
        actionProc.running = true;
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: rootObj.s(14)

            Text {
                text: "BITE-OS"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(22)
                color: ThemeBackend.text
            }

            Text {
                text: "GLITCH-BITE-404  ·  github.com/GLITCH-BITE-404/BITE-OS"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: infoCol.implicitHeight + rootObj.s(16)
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.55)

                ColumnLayout {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(4)

                    Text {
                        text: "active rice:  " + biteTabRoot.activeRice
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.green
                    }
                    Text {
                        text: "active shell: " + biteTabRoot.activeShell
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext1
                    }
                    Text {
                        visible: biteTabRoot.statusLine !== ""
                        text: biteTabRoot.statusLine
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.peach
                    }
                }
            }

            Text {
                text: "Save keeps your keybinds, theme and layout in the vault. Without it a rice swap reverts them."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
            }

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(38)
                buttonText: "Save this rice"
                buttonIcon: "󰆓"
                accentColor: ThemeBackend.green
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                textColor: ThemeBackend.green
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(12)
                iconFontSize: rootObj.s(16)
                fillDuration: 900
                onTriggered: biteTabRoot.runAction("Saved rice",
                    "~/.config/glitch/bin/rice save \"$(cat ~/.local/share/bite-os/rices/.active)\" --force")
            }

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(38)
                buttonText: "Roll back last swap"
                buttonIcon: "󰕌"
                accentColor: ThemeBackend.peach
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                textColor: ThemeBackend.peach
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(12)
                iconFontSize: rootObj.s(16)
                fillDuration: 1400
                onTriggered: biteTabRoot.runAction("Rolled back",
                    "~/.config/glitch/bin/rice rollback")
            }

            Text {
                text: "Switch rice"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(13)
                color: ThemeBackend.text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: rootObj.s(8)

                FillButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: rootObj.s(36)
                    buttonText: "caelestia"
                    buttonIcon: "󰋜"
                    accentColor: ThemeBackend.blue
                    baseColor: ThemeBackend.surface0
                    hoverColor: Qt.alpha(ThemeBackend.blue, 0.15)
                    textColor: ThemeBackend.blue
                    filledTextColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    textFontSize: rootObj.s(11)
                    iconFontSize: rootObj.s(14)
                    fillDuration: 1400
                    onTriggered: biteTabRoot.runAction("Swapping to caelestia",
                        "~/.config/glitch/bin/dots-switch.sh caelestia")
                }

                FillButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: rootObj.s(36)
                    buttonText: "ilyamiro"
                    buttonIcon: "󰋜"
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface0
                    hoverColor: Qt.alpha(ThemeBackend.mauve, 0.15)
                    textColor: ThemeBackend.mauve
                    filledTextColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    textFontSize: rootObj.s(11)
                    iconFontSize: rootObj.s(14)
                    fillDuration: 1400
                    onTriggered: biteTabRoot.runAction("Swapping to ilyamiro",
                        "~/.config/glitch/bin/dots-switch.sh ilyamiro")
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
