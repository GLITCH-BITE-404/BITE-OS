pragma ComponentBehavior: Bound

import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

Item {
    id: root

    required property Session session

    property string activeShell: "caelestia"
    readonly property bool serpantinumActive: activeShell === "serpantinum"
    property bool initialised: false
    property bool swapping: false

    function refresh() {
        activeReader.running = true;
    }

    Process {
        id: activeReader
        running: true
        command: ["sh", "-c", "cat ~/.local/state/bite-os/active-shell 2>/dev/null || echo caelestia"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.activeShell = text.trim() || "caelestia";
                root.initialised = true;
                root.swapping = false;
            }
        }
    }
    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    function pickShell(target) {
        if (!root.initialised) return;
        if (root.activeShell === target) return;
        root.swapping = true;
        Quickshell.execDetached([
            "sh", "-c",
            "~/.config/glitch/bin/dots-switch.sh " + target
        ]);
    }

    StyledFlickable {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.large
        contentHeight: column.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Tokens.spacing.large

            // ── header ─────────────────────────────────────────────
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Dots")
                color: Colours.palette.m3onSurface
                font.pointSize: Tokens.font.size.title
                font.bold: true
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Swap your entire desktop between caelestia and serpantinum. Your current rice is auto-backed-up before every swap. Press Super+Ctrl+D anywhere to revert if anything breaks.")
                wrapMode: Text.WordWrap
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.normal
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.5
            }

            // ── status row ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.normal

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.swapping ? Colours.palette.m3secondary
                         : root.serpantinumActive ? Colours.palette.m3primary
                                                : Colours.palette.m3tertiary
                    SequentialAnimation on opacity {
                        running: root.swapping
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.3; duration: 500 }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 500 }
                    }
                }

                StyledText {
                    text: root.swapping ? qsTr("Swapping…")
                                        : qsTr("Active: ") + root.activeShell
                    color: Colours.palette.m3onSurface
                    font.pointSize: Tokens.font.size.normal
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
            }

            // ── option cards ───────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Tokens.spacing.normal
                rowSpacing: Tokens.spacing.normal

                // Card: caelestia
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: Tokens.rounding.normal
                    color: !root.serpantinumActive ? Colours.palette.m3primaryContainer
                                                : Colours.palette.m3surfaceContainerHigh
                    border.width: !root.serpantinumActive ? 2 : 1
                    border.color: !root.serpantinumActive ? Colours.palette.m3primary
                                                        : Colours.palette.m3outlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.normal
                        spacing: 4

                        StyledText {
                            text: qsTr("caelestia")
                            font.pointSize: Tokens.font.size.large
                            font.bold: true
                            color: !root.serpantinumActive ? Colours.palette.m3onPrimaryContainer
                                                        : Colours.palette.m3onSurface
                        }
                        StyledText {
                            text: qsTr("your personal rice")
                            font.pointSize: Tokens.font.size.small
                            color: !root.serpantinumActive ? Colours.palette.m3onPrimaryContainer
                                                        : Colours.palette.m3onSurfaceVariant
                            opacity: 0.85
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            text: !root.serpantinumActive ? qsTr("● active") : qsTr("click to switch")
                            font.pointSize: Tokens.font.size.small
                            color: !root.serpantinumActive ? Colours.palette.m3primary
                                                        : Colours.palette.m3onSurfaceVariant
                            font.bold: !root.serpantinumActive
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.initialised && !root.swapping
                        onClicked: root.pickShell("caelestia")
                    }
                }

                // Card: serpantinum
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: Tokens.rounding.normal
                    color: root.serpantinumActive ? Colours.palette.m3primaryContainer
                                                : Colours.palette.m3surfaceContainerHigh
                    border.width: root.serpantinumActive ? 2 : 1
                    border.color: root.serpantinumActive ? Colours.palette.m3primary
                                                        : Colours.palette.m3outlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.normal
                        spacing: 4

                        StyledText {
                            text: qsTr("serpantinum")
                            font.pointSize: Tokens.font.size.large
                            font.bold: true
                            color: root.serpantinumActive ? Colours.palette.m3onPrimaryContainer
                                                        : Colours.palette.m3onSurface
                        }
                        StyledText {
                            text: qsTr("wayland shell \u00b7 v2")
                            font.pointSize: Tokens.font.size.small
                            color: root.serpantinumActive ? Colours.palette.m3onPrimaryContainer
                                                        : Colours.palette.m3onSurfaceVariant
                            opacity: 0.85
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            text: root.serpantinumActive ? qsTr("● active") : qsTr("click to switch")
                            font.pointSize: Tokens.font.size.small
                            color: root.serpantinumActive ? Colours.palette.m3primary
                                                        : Colours.palette.m3onSurfaceVariant
                            font.bold: root.serpantinumActive
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.initialised && !root.swapping
                        onClicked: root.pickShell("serpantinum")
                    }
                }
            }

            // ── safety notes ───────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: notesCol.implicitHeight + Tokens.spacing.normal * 2
                radius: Tokens.rounding.normal
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.6)
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                ColumnLayout {
                    id: notesCol
                    anchors.fill: parent
                    anchors.margins: Tokens.spacing.normal
                    spacing: 6

                    StyledText {
                        text: qsTr("Safety")
                        font.pointSize: Tokens.font.size.normal
                        font.bold: true
                        color: Colours.palette.m3onSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("• Each swap auto-backs-up your current configs before installing the target rice. Backups live at ~/.local/share/bite-os/rices/_autobackup/ and are never deleted.")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("• A watchdog checks that the target shell is alive 30 seconds after swap. If it isn't, it auto-reverts to caelestia so you never get a black screen.")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("• Press Super+Ctrl+D at any time to flip back. The keybind is wired into both rices' hyprland config.")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("• Worst-case escape from a TTY: run `~/.config/glitch/bin/dots-switch.sh caelestia`")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
