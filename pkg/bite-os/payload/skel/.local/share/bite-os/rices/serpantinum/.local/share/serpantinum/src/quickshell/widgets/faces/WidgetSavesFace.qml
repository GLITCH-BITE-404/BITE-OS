// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
//  Desktop widget: your newest widget-layout saves (3 by default, set in the
//  Widgets settings tab) with hold-to-Load and Save now. Backed by
//  ~/.config/hypr/scripts/widget-saves.sh; loading rebuilds the widgets through
//  the shell's widget IPC (no restart) and auto-saves the current layout first.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 240
    property real minHeight: 150
    property real maxWidth: 640
    property real maxHeight: 560
    property real minAspect: 0.7
    property real maxAspect: 3.2
    property bool isRound: false

    BiteWidgetConfig { id: bcfg }
    readonly property int showCount: Math.max(1, Math.min(10, Math.round(bcfg.get("widgetSaves.count", 3))))
    readonly property string tool: "\"$HOME/.config/hypr/scripts/widget-saves.sh\""

    readonly property string icWidgets:  String.fromCodePoint(0xF0570)
    readonly property string icSave:     String.fromCodePoint(0xF0193)
    readonly property string icRollback: String.fromCodePoint(0xF054C)

    property string statusLine: ""
    property bool busy: false
    property var rows: []

    function refresh() { if (!listProc.running) listProc.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    onShowCountChanged: refresh()
    Timer { interval: 5000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    Process {
        id: listProc
        running: false
        command: ["bash", "-c", root.tool + " list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of (this.text || "").trim().split("\n")) {
                    const p = l.split("\t");   // id name when count kind
                    if (p.length < 5) continue;
                    out.push({ sid: p[0], name: p[1], when: p[2], count: parseInt(p[3]) || 0, auto: p[4] === "auto" });
                    if (out.length >= root.showCount) break;
                }
                if (JSON.stringify(out) !== JSON.stringify(root.rows)) root.rows = out;
            }
        }
    }

    Process {
        id: actionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                root.statusLine = (this.text || "").trim().split("\n").pop() || "done";
                clearStatus.restart();
                root.refresh();
            }
        }
    }
    Timer { id: clearStatus; interval: 4000; onTriggered: root.statusLine = "" }

    function run(label, args) {
        if (root.busy) return;
        root.busy = true;
        root.statusLine = label + "…";
        actionProc.command = ["bash", "-c", root.tool + " " + args + " 2>&1"];
        actionProc.running = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: ThemeBackend.surface0
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.green, 0.25)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(12)
            spacing: Scaler.s(8)

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)
                Text { text: root.icWidgets; font.family: "Iosevka Nerd Font"; font.pixelSize: Scaler.s(14); color: ThemeBackend.green }
                Text { text: "widget layouts"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.subtext0 }
                Item { Layout.fillWidth: true }
            }

            Repeater {
                model: root.rows
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Scaler.s(8)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Scaler.s(6)
                            Text {
                                text: modelData.name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: Scaler.s(12)
                                color: ThemeBackend.text
                            }
                            Rectangle {
                                visible: modelData.auto
                                implicitWidth: autoTxt.implicitWidth + Scaler.s(12)
                                implicitHeight: autoTxt.implicitHeight + Scaler.s(4)
                                radius: height / 2
                                color: Qt.alpha(ThemeBackend.mauve, 0.18)
                                Text { id: autoTxt; anchors.centerIn: parent; text: "auto"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(9); font.bold: true; color: ThemeBackend.mauve }
                            }
                        }
                        Text {
                            text: modelData.when + "  ·  " + modelData.count + (modelData.count === 1 ? " widget" : " widgets")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(10)
                            color: ThemeBackend.subtext0
                        }
                    }

                    FillButton {
                        Layout.preferredWidth: Scaler.s(78)
                        Layout.preferredHeight: Scaler.s(30)
                        buttonText: "Load"
                        buttonIcon: root.icRollback
                        textFontSize: Scaler.s(11)
                        iconFontSize: Scaler.s(13)
                        accentColor: ThemeBackend.peach
                        baseColor: ThemeBackend.surface1
                        hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                        textColor: ThemeBackend.peach
                        filledTextColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        fillDuration: 900
                        onTriggered: if (/^[0-9]{8}-[0-9]+$/.test(modelData.sid)) root.run("loading " + modelData.name, "load " + modelData.sid)
                    }
                }
            }

            Text {
                visible: root.rows.length === 0
                text: "no widget saves yet"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: ThemeBackend.subtext0
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    Layout.fillWidth: true
                    text: root.statusLine
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.peach
                }
                ClickButton {
                    Layout.preferredWidth: Scaler.s(110)
                    Layout.preferredHeight: Scaler.s(32)
                    buttonText: root.busy ? "…" : "Save now"
                    buttonIcon: root.icSave
                    textFontSize: Scaler.s(12)
                    iconFontSize: Scaler.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.green
                    onTriggered: root.run("saving", "save")
                }
            }
        }
    }
}
