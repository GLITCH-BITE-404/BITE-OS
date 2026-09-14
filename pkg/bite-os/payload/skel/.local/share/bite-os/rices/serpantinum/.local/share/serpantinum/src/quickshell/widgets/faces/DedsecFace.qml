// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Desktop widget: a dedsec-style readout of the same SysData
//  feed UsageFace uses. Three looks, picked by `look` (the Bars and Hex
//  variants are thin files that set it):
//    terminal  prompt + block-character bars + blinking cursor
//    bars      four LED-segment meters
//    hex       the live readout encoded as a hex dump
//
//  60fps budget: text only changes when SysData ticks (~1s); meters animate
//  height only while visible; the cursor blink and title glitch are timer
//  swaps; the scanlines/segments are Canvases painted once per resize.
//  Everything stops while hidden.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property string look: "terminal"

    property real minWidth: 260
    property real minHeight: 170
    property real maxWidth: 720
    property real maxHeight: 480
    property real minAspect: 1.1
    property real maxAspect: 3.2
    property bool isRound: false

    // ── data ────────────────────────────────────────────────────────────────
    property bool isSubscribed: false

    function updateSubscription() {
        if (root.visible && !root.isSubscribed) {
            SysData.subscribe();
            root.isSubscribed = true;
        } else if (!root.visible && root.isSubscribed) {
            SysData.unsubscribe();
            root.isSubscribed = false;
        }
    }

    onVisibleChanged: updateSubscription()
    Component.onCompleted: {
        updateSubscription();
        if (typeof SystemInfo !== "undefined") SystemInfo.fetch();
    }
    Component.onDestruction: {
        if (root.isSubscribed) {
            SysData.unsubscribe();
            root.isSubscribed = false;
        }
    }

    readonly property real cpu:  isNaN(SysData.cpu) ? 0 : SysData.cpu / 100
    readonly property real ram:  isNaN(SysData.ramPercent) ? 0 : SysData.ramPercent / 100
    readonly property real disk: isNaN(SysData.diskPercent) ? 0 : SysData.diskPercent / 100
    readonly property real temp: isNaN(SysData.temp) ? 0 : SysData.temp
    readonly property real ramGb: isNaN(SysData.ramGb) ? 0 : SysData.ramGb
    readonly property real netRx: isNaN(SysData.netRx) ? 0 : SysData.netRx
    readonly property real netTx: isNaN(SysData.netTx) ? 0 : SysData.netTx

    readonly property string host: (typeof SystemInfo !== "undefined" && SystemInfo.hostname !== "") ? SystemInfo.hostname : "bite-os"
    readonly property string uptime: (typeof SystemInfo !== "undefined" && SystemInfo.uptime !== "") ? SystemInfo.uptime : "…"

    function formatBytes(bytes) {
        if (bytes <= 0 || isNaN(bytes)) return "0 B/s";
        let k = 1024, sizes = ["B/s", "KB/s", "MB/s", "GB/s"];
        let i = Math.min(sizes.length - 1, Math.floor(Math.log(bytes) / Math.log(k)));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
    }

    // one place that maps a meter name to its value, for the bars/hex looks
    function fracFor(k) {
        return k === "CPU" ? root.cpu : k === "RAM" ? root.ram : k === "DSK" ? root.disk : Math.min(1, root.temp / 100);
    }
    function valueFor(k) {
        return k === "CPU" ? Math.round(root.cpu * 100) + "%"
             : k === "RAM" ? root.ramGb.toFixed(1) + "G"
             : k === "DSK" ? Math.round(root.disk * 100) + "%"
             : Math.round(root.temp) + "C";
    }

    // ── look ────────────────────────────────────────────────────────────────
    readonly property color cAccent: ThemeBackend.green
    readonly property color cWarn:   ThemeBackend.peach
    readonly property color cHot:    ThemeBackend.red
    readonly property color cDim:    ThemeBackend.subtext0
    readonly property color cText:   ThemeBackend.text
    readonly property string mono:   ThemeBackend.fontFamily

    function tone(frac) { return frac >= 0.85 ? root.cHot : (frac >= 0.6 ? root.cWarn : root.cAccent); }

    readonly property real pad: Scaler.s(12)
    // 8 lines have to fit; the font follows the widget's height
    readonly property real fs: Math.max(Scaler.s(9), Math.min(Scaler.s(15), (root.height - 2 * pad) / (8 * 1.45)))

    TextMetrics {
        id: cellMetrics
        font.family: root.mono
        font.pixelSize: root.fs
        text: "█"
    }
    // columns that fit, minus "CPU  [" + "] 100%"
    readonly property int barCells: Math.max(4, Math.floor((root.width - 2 * pad) / Math.max(1, cellMetrics.advanceWidth)) - 12)

    function bar(frac) {
        let n = Math.round(Math.max(0, Math.min(1, frac)) * root.barCells);
        return "█".repeat(n) + "░".repeat(root.barCells - n);
    }

    // ── title glitch ────────────────────────────────────────────────────────
    readonly property string titleClean: root.look === "hex" ? "xxd /dev/sys" : "sysmon"
    property string titleShown: titleClean
    onTitleCleanChanged: titleShown = titleClean
    readonly property string junk: "#$%&@!?/<>*"

    Timer {
        id: glitchTimer
        interval: 3500 + Math.floor(Math.random() * 2500)
        repeat: true
        running: root.visible
        onTriggered: {
            let t = root.titleClean.split("");
            for (let k = 0; k < 2; k++) {
                t[Math.floor(Math.random() * t.length)] = root.junk[Math.floor(Math.random() * root.junk.length)];
            }
            root.titleShown = t.join("");
            glitchRestore.restart();
            interval = 3500 + Math.floor(Math.random() * 2500);
        }
    }
    Timer {
        id: glitchRestore
        interval: 90
        onTriggered: root.titleShown = root.titleClean
    }

    component Mono: Text {
        font.family: root.mono
        font.pixelSize: root.fs
        color: root.cText
    }

    component Prompt: Row {
        spacing: 0
        Mono { text: "root@" + root.host; font.bold: true; color: root.cAccent }
        Mono { text: ":~$ "; color: root.cDim }
        Mono { text: root.titleShown }
    }

    component Cursor: Row {
        spacing: 0
        Mono { text: "> "; color: root.cAccent }
        Mono {
            text: "█"
            color: root.cAccent
            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 80 }
                PauseAnimation { duration: 450 }
                NumberAnimation { to: 1; duration: 80 }
                PauseAnimation { duration: 450 }
            }
        }
    }

    // ── card ────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.92)
        border.width: 1
        border.color: Qt.alpha(root.cAccent, 0.35)
        clip: true

        // static scanlines: painted once per resize, zero per-frame cost
        Canvas {
            anchors.fill: parent
            opacity: 0.06
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.cAccent.toString();
                for (let y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1);
            }
        }

        // ── terminal look ───────────────────────────────────────────────────
        ColumnLayout {
            visible: root.look === "terminal"
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: Math.round(root.fs * 0.3)

            Prompt {}

            component BarLine: Row {
                id: bl
                property string label: ""
                property real frac: 0
                property string value: ""
                spacing: 0
                Mono { text: bl.label; color: root.cDim }
                Mono { text: "["; color: root.cDim }
                Mono { text: root.bar(bl.frac); color: root.tone(bl.frac) }
                Mono { text: "] " + bl.value }
            }

            BarLine { label: "CPU  "; frac: root.cpu;  value: Math.round(root.cpu * 100) + "%" }
            BarLine { label: "RAM  "; frac: root.ram;  value: root.ramGb.toFixed(1) + "G" }
            BarLine { label: "DISK "; frac: root.disk; value: Math.round(root.disk * 100) + "%" }

            Row {
                spacing: 0
                Mono { text: "TEMP "; color: root.cDim }
                Mono { text: Math.round(root.temp) + "°C"; color: root.tone(root.temp / 100) }
            }
            Row {
                spacing: 0
                Mono { text: "NET  "; color: root.cDim }
                Mono { text: "↓ " + root.formatBytes(root.netRx) + "  ↑ " + root.formatBytes(root.netTx) }
            }
            Row {
                spacing: 0
                Mono { text: "UP   "; color: root.cDim }
                Mono { text: root.uptime }
            }

            Cursor {}

            Item { Layout.fillHeight: true }
        }

        // ── bars look: four LED-segment meters ──────────────────────────────
        ColumnLayout {
            visible: root.look === "bars"
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: Scaler.s(8)

            Row {
                spacing: 0
                Mono { text: "sysmon"; font.bold: true; color: root.cAccent }
                Mono { text: " // " + root.host; color: root.cDim }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Scaler.s(10)

                Repeater {
                    model: ["CPU", "RAM", "DSK", "TMP"]

                    ColumnLayout {
                        id: meter
                        required property string modelData
                        readonly property real frac: root.fracFor(modelData)
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Scaler.s(4)

                        Mono {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.valueFor(meter.modelData)
                            font.bold: true
                            color: root.tone(meter.frac)
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.fill: parent
                                radius: Scaler.s(4)
                                color: Qt.alpha(ThemeBackend.surface0, 0.7)
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * Math.max(0, Math.min(1, meter.frac))
                                radius: Scaler.s(4)
                                color: root.tone(meter.frac)
                                Behavior on height { enabled: root.visible; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 400 } }
                            }
                            // segment gaps, painted once per resize
                            Canvas {
                                anchors.fill: parent
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    let ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.fillStyle = ThemeBackend.crust.toString();
                                    let step = Math.max(4, Math.round(Scaler.s(7)));
                                    for (let y = height - step; y > 0; y -= step) ctx.fillRect(0, y, width, Math.max(1, Math.round(step * 0.28)));
                                }
                            }
                        }

                        Mono {
                            Layout.alignment: Qt.AlignHCenter
                            text: meter.modelData
                            color: root.cDim
                        }
                    }
                }
            }
        }

        // ── hex look: the readout as a live hex dump ────────────────────────
        ColumnLayout {
            visible: root.look === "hex"
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: Math.round(root.fs * 0.3)

            Prompt {}

            Repeater {
                model: ["CPU", "RAM", "DSK", "TMP"]

                Row {
                    id: hexRow
                    required property string modelData
                    required property int index
                    // exactly 7 chars, e.g. "CPU 48%"
                    readonly property string ascii: (modelData + " " + root.valueFor(modelData)).padEnd(7, " ").slice(0, 7)
                    readonly property string bytes: ascii.split("").map(c => c.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0")).join(" ")
                    spacing: 0
                    Mono { text: (index * 16).toString(16).padStart(4, "0") + "  "; color: root.cDim }
                    Mono { text: hexRow.bytes; color: root.tone(root.fracFor(hexRow.modelData)) }
                    Mono { text: "  |" + hexRow.ascii + "|"; color: root.cDim }
                }
            }

            Row {
                spacing: 0
                Mono { text: "0040  "; color: root.cDim }
                Mono { text: "↓" + root.formatBytes(root.netRx) + " ↑" + root.formatBytes(root.netTx) }
            }

            Cursor {}

            Item { Layout.fillHeight: true }
        }
    }
}
