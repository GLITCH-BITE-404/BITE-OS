// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
//  Desktop widget: a live map of your Hyprland workspaces -- one tile per
//  workspace with its number, a dot per window and the top window's title.
//  The focused tile glows and pulses, empty ones dim, a click jumps there.
//
//  Zero polling: Quickshell.Hyprland updates on Hyprland's own events. The
//  pulse is one opacity animation that only runs while the widget is visible.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 220
    property real minHeight: 110
    property real maxWidth: 1000
    property real maxHeight: 560
    property real minAspect: 1.0
    property real maxAspect: 6.0
    property bool isRound: false

    BiteWidgetConfig { id: bcfg }
    readonly property int count: Math.max(2, Math.min(10, Math.round(bcfg.get("workspaceMap.count", 8))))
    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property int cols: count <= 5 ? count : Math.ceil(count / 2)
    readonly property int rowsN: Math.ceil(count / cols)

    function wsFor(id) {
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++)
            if (all[i].id === id) return all[i];
        return null;
    }

    readonly property color cAccent: ThemeBackend.mauve

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.9)
        border.width: 1
        border.color: Qt.alpha(root.cAccent, 0.3)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(10)
            spacing: Scaler.s(8)

            RowLayout {
                Layout.fillWidth: true
                Text { text: "workspaces"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: root.cAccent }
                Text { text: " // map"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); color: ThemeBackend.subtext0 }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.focusedId > 0 ? ("on " + root.focusedId) : ""
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.subtext0
                }
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: root.cols
                rowSpacing: Scaler.s(6)
                columnSpacing: Scaler.s(6)

                Repeater {
                    model: root.count

                    Rectangle {
                        id: tile
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property var ws: root.wsFor(wsId)
                        readonly property var wins: (ws && ws.toplevels) ? ws.toplevels.values : []
                        readonly property bool focused: wsId === root.focusedId
                        readonly property bool occupied: wins.length > 0

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Scaler.s(8)
                        color: focused ? Qt.alpha(root.cAccent, 0.22)
                             : occupied ? Qt.alpha(ThemeBackend.surface1, 0.85)
                             : Qt.alpha(ThemeBackend.surface0, 0.45)
                        border.width: focused ? 2 : 1
                        border.color: focused ? root.cAccent : Qt.alpha(ThemeBackend.overlay0, occupied ? 0.5 : 0.25)
                        Behavior on color { ColorAnimation { duration: 180 } }

                        // pulse on the focused tile (one opacity animation)
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: root.cAccent
                            visible: tile.focused
                            SequentialAnimation on opacity {
                                running: tile.focused && root.visible
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.9; to: 0.15; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.15; to: 0.9; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Scaler.s(6)
                            text: tile.wsId
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(tile.focused ? 16 : 13)
                            font.bold: true
                            color: tile.focused ? root.cAccent : (tile.occupied ? ThemeBackend.text : ThemeBackend.overlay1)
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Scaler.s(8)
                            spacing: Scaler.s(3)
                            Repeater {
                                model: Math.min(tile.wins.length, 6)
                                Rectangle {
                                    width: Scaler.s(6); height: width; radius: width / 2
                                    color: tile.focused ? root.cAccent : ThemeBackend.green
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Scaler.s(6)
                            visible: tile.occupied && tile.height > Scaler.s(44)
                            text: tile.occupied ? (tile.wins[0].title || "") : ""
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(9)
                            color: ThemeBackend.subtext0
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch("workspace " + tile.wsId)
                        }
                    }
                }
            }
        }
    }
}
