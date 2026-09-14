// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
//  Desktop widget: your newest rice saves (2 by default -- set in the Widgets
//  settings tab, independent of the vault's history limit), Save, and a
//  hold-to-confirm Load that brings an older save back and applies it.
//  Load = `rice restore <id>` + dots-switch.sh, which restarts this very
//  shell, so it runs under `setsid -f`.
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
    readonly property int showCount: Math.max(1, Math.min(10, Math.round(bcfg.get("riceSaves.count", 2))))

    readonly property string icHistory:  String.fromCodePoint(0xF02DA)
    readonly property string icSave:     String.fromCodePoint(0xF0193)
    readonly property string icRollback: String.fromCodePoint(0xF054C)

    property string activeRice: ""
    property string statusLine: ""
    property bool busy: false
    property var rows: []

    function refresh() { if (!stateProc.running) stateProc.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    onShowCountChanged: refresh()
    Timer { interval: 5000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    function when(s) {
        const b = (s || "").split("-");
        return (b.length === 2 && b[0].length === 8 && b[1].length >= 4)
            ? b[0].slice(4, 6) + "/" + b[0].slice(6, 8) + " " + b[1].slice(0, 2) + ":" + b[1].slice(2, 4) : "";
    }

    // current vault save + this rice's snapshots, by their OWN saved= time
    Process {
        id: stateProc
        running: false
        command: ["bash", "-c",
            "V=\"$HOME/.local/share/bite-os/rices\"; A=$(cat \"$V/.active\" 2>/dev/null); " +
            "m() { sed -n \"s/^$1=//p\" \"$2\" 2>/dev/null | head -n 1; }; echo \"ACTIVE=$A\"; " +
            "[ -n \"$A\" ] && [ -f \"$V/$A/meta.txt\" ] && printf 'CUR\\t-\\t%s\\t%s\\n' \"$(m saved \"$V/$A/meta.txt\")\" \"$(m label \"$V/$A/meta.txt\")\"; " +
            "for d in \"$V\"/_replaced/\"$A\"-*/; do [ -d \"$d\" ] || continue; id=$(basename \"$d\"); " +
            "s=$(m saved \"$d/meta.txt\"); [ -n \"$s\" ] || s=${id: -15}; " +
            "printf 'OLD\\t%s\\t%s\\t%s\\n' \"$id\" \"$s\" \"$(m label \"$d/meta.txt\")\"; done | sort -t$'\\t' -k3,3r"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of (this.text || "").trim().split("\n")) {
                    if (l.indexOf("ACTIVE=") === 0) { root.activeRice = l.slice(7).trim(); continue; }
                    const p = l.split("\t");
                    if (p.length < 3 || (p[0] !== "CUR" && p[0] !== "OLD")) continue;
                    out.push({ sid: p[1], iscur: p[0] === "CUR", when: root.when(p[2]),
                               label: p[3] || (p[0] === "CUR" ? "current save" : "unnamed save") });
                    if (out.length >= root.showCount) break;
                }
                if (JSON.stringify(out) !== JSON.stringify(root.rows)) root.rows = out;
            }
        }
    }

    Process {
        id: saveProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                root.statusLine = (this.text || "").indexOf("no changes") !== -1 ? "no changes since the last save" : "saved";
                clearStatus.restart();
                root.refresh();
            }
        }
    }
    Timer { id: clearStatus; interval: 4000; onTriggered: root.statusLine = "" }

    function saveRice() {
        if (root.busy || !/^[A-Za-z0-9_-]+$/.test(root.activeRice)) return;
        root.busy = true;
        root.statusLine = "saving…";
        saveProc.command = ["bash", "-c", "\"$HOME/.config/glitch/bin/rice\" save " + root.activeRice + " -m 'widget save' --force 2>&1"];
        saveProc.running = true;
    }

    function loadSave(sid, label) {
        if (!/^[A-Za-z0-9_-]+-[0-9]{8}-[0-9]{6}$/.test(sid) || !/^[A-Za-z0-9_-]+$/.test(root.activeRice)) return;
        root.statusLine = "loading " + label + "…";
        Quickshell.execDetached(["setsid", "-f", "bash", "-c",
            "\"$HOME/.config/glitch/bin/rice\" restore '" + sid + "' && \"$HOME/.config/glitch/bin/dots-switch.sh\" " + root.activeRice + " >/dev/null 2>&1"]);
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: ThemeBackend.surface0
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.mauve, 0.25)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(12)
            spacing: Scaler.s(8)

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)
                Text { text: root.icHistory; font.family: "Iosevka Nerd Font"; font.pixelSize: Scaler.s(14); color: ThemeBackend.mauve }
                Text { text: "rice saves"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.subtext0 }
                Item { Layout.fillWidth: true }
                Text { text: root.activeRice; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.mauve }
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
                                text: modelData.label
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: Scaler.s(12)
                                font.bold: modelData.iscur
                                color: ThemeBackend.text
                            }
                            Rectangle {
                                visible: modelData.iscur
                                implicitWidth: curTxt.implicitWidth + Scaler.s(12)
                                implicitHeight: curTxt.implicitHeight + Scaler.s(4)
                                radius: height / 2
                                color: Qt.alpha(ThemeBackend.green, 0.18)
                                Text { id: curTxt; anchors.centerIn: parent; text: "current"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(9); font.bold: true; color: ThemeBackend.green }
                            }
                        }
                        Text { text: modelData.when; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(10); color: ThemeBackend.subtext0 }
                    }

                    FillButton {
                        // hold to confirm: brings this save back and restarts the shell
                        visible: !modelData.iscur
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
                        fillDuration: 1200
                        onTriggered: root.loadSave(modelData.sid, modelData.label)
                    }
                }
            }

            Text {
                visible: root.rows.length === 0
                text: "no saves yet"
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
                    Layout.preferredWidth: Scaler.s(96)
                    Layout.preferredHeight: Scaler.s(32)
                    buttonText: root.busy ? "…" : "Save"
                    buttonIcon: root.icSave
                    textFontSize: Scaler.s(12)
                    iconFontSize: Scaler.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.green
                    onTriggered: root.saveRice()
                }
            }
        }
    }
}
