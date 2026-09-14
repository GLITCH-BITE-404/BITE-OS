// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
//  Desktop widget: a live `top` -- the processes eating your CPU right now,
//  terminal style: name, a block bar coloured by load, CPU % and memory %.
//
//  Cost: one `top -b -n 1` every 2 s, and only while the widget is visible.
//  Rows update in place, so nothing flickers or re-lays out between samples.
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
    property real maxWidth: 720
    property real maxHeight: 560
    property real minAspect: 0.9
    property real maxAspect: 3.5
    property bool isRound: false

    BiteWidgetConfig { id: bcfg }
    readonly property int rowsN: Math.max(3, Math.min(10, Math.round(bcfg.get("procTop.rows", 6))))

    readonly property color cAccent: ThemeBackend.green
    readonly property string mono: ThemeBackend.fontFamily
    readonly property real pad: Scaler.s(12)
    readonly property real fs: Math.max(Scaler.s(9), Math.min(Scaler.s(14), (root.height - 2 * pad) / ((rowsN + 1.6) * 1.5)))

    property var procs: []

    function tone(frac) { return frac >= 0.6 ? ThemeBackend.red : (frac >= 0.25 ? ThemeBackend.peach : root.cAccent); }

    TextMetrics { id: cell; font.family: root.mono; font.pixelSize: root.fs; text: "█" }
    // columns left for the bar after "name(14) " and " 100.0%  12.3%"
    readonly property int barCells: Math.max(3, Math.floor((root.width - 2 * pad) / Math.max(1, cell.advanceWidth)) - 30)
    function bar(frac) {
        const n = Math.round(Math.max(0, Math.min(1, frac)) * root.barCells);
        return "█".repeat(n) + "░".repeat(root.barCells - n);
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: if (!topProc.running) topProc.running = true
    }

    Process {
        id: topProc
        running: false
        command: ["bash", "-c", "LC_ALL=C top -b -n 1 -w 256 -o %CPU | awk 'f && NF>=12 {c=$9; m=$10; $1=$2=$3=$4=$5=$6=$7=$8=$9=$10=$11=\"\"; sub(/^ +/,\"\"); print c\"\\t\"m\"\\t\"$0} /^ *PID /{f=1}' | head -n " + root.rowsN]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of (this.text || "").trim().split("\n")) {
                    const p = l.split("\t");
                    if (p.length < 3) continue;
                    out.push({ cpu: parseFloat(p[0]) || 0, mem: parseFloat(p[1]) || 0, name: p[2] });
                }
                root.procs = out;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.92)
        border.width: 1
        border.color: Qt.alpha(root.cAccent, 0.35)
        clip: true

        // static scanlines, painted once per resize
        Canvas {
            anchors.fill: parent
            opacity: 0.05
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.cAccent.toString();
                for (let y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1);
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: Math.round(root.fs * 0.35)

            Row {
                Text { text: "root@" + (Quickshell.env("HOSTNAME") || "bite-os"); font.family: root.mono; font.pixelSize: root.fs; font.bold: true; color: root.cAccent }
                Text { text: ":~$ "; font.family: root.mono; font.pixelSize: root.fs; color: ThemeBackend.subtext0 }
                Text { text: "top"; font.family: root.mono; font.pixelSize: root.fs; color: ThemeBackend.text }
            }

            Row {
                Text {
                    text: "PROCESS        " + " ".repeat(root.barCells) + "   CPU    MEM"
                    font.family: root.mono
                    font.pixelSize: root.fs
                    color: ThemeBackend.overlay1
                }
            }

            Repeater {
                model: root.rowsN
                Row {
                    required property int index
                    readonly property var p: index < root.procs.length ? root.procs[index] : null
                    readonly property real frac: p ? Math.min(1, p.cpu / 100) : 0
                    spacing: 0
                    Text {
                        text: p ? (p.name + "              ").substring(0, 14) + " " : ""
                        font.family: root.mono
                        font.pixelSize: root.fs
                        color: ThemeBackend.text
                    }
                    Text {
                        text: p ? root.bar(frac) : ""
                        font.family: root.mono
                        font.pixelSize: root.fs
                        color: root.tone(frac)
                    }
                    Text {
                        text: p ? (" " + p.cpu.toFixed(1).padStart(5) + "%") : ""
                        font.family: root.mono
                        font.pixelSize: root.fs
                        color: root.tone(frac)
                    }
                    Text {
                        text: p ? ("  " + p.mem.toFixed(1).padStart(4) + "%") : ""
                        font.family: root.mono
                        font.pixelSize: root.fs
                        color: ThemeBackend.subtext0
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
