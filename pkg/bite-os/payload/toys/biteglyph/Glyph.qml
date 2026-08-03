// biteglyph — the window. convert.py does all the real work.
//
// QML can read and write files but cannot start a process, so the two halves
// talk through this directory: we write request.json, the engine notices,
// renders preview.png and writes status.json back. The launcher cd's here
// first, which is why every path below is relative.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: win
    visible: true
    width: 1180
    height: 720
    title: "biteglyph"
    color: "#07090b"

    readonly property color accent:  "#00e676"
    readonly property color dim:     "#5a6b60"
    readonly property color panel:   "#0d1114"
    readonly property color stroke:  "#1b2a22"

    property string inputPath: ""
    property int    seq: 0
    property int    lastSeen: -1
    property bool   busy: false
    property string note: "drop a picture, gif or video in"
    property int    srcFrames: 1
    property bool   animated: false

    // ── settings the engine cares about ──
    property int    cols: 120
    property string charset: "ascii"
    property bool   colour: true
    property bool   invert: false
    property real   contrast: 1.0
    property string cut: "off"
    property bool   transparent: false
    property int    frameNo: 0

    function here(name) {
        return Qt.resolvedUrl(name).toString().replace("file://", "")
    }

    function push(extra) {
        if (!inputPath) return
        seq += 1
        var body = {
            input: inputPath, width: cols, charset: charset, colour: colour,
            invert: invert, contrast: contrast, cut: cut,
            transparent: transparent, frame: frameNo, cell: 10, seq: seq
        }
        for (var k in extra) body[k] = extra[k]
        busy = true
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify(body))
    }

    // Coalesce slider drags — one render per pause, not one per pixel.
    Timer {
        id: debounce
        interval: 140
        onTriggered: win.push({})
    }
    function queue() { debounce.restart() }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            var x = new XMLHttpRequest()
            x.open("GET", "file://" + here("status.json"))
            x.onreadystatechange = function () {
                if (x.readyState !== XMLHttpRequest.DONE || !x.responseText) return
                var s
                try { s = JSON.parse(x.responseText) } catch (e) { return }
                if (s.seq === undefined || s.seq === win.lastSeen) return
                win.lastSeen = s.seq
                win.busy = false
                if (!s.ok) { win.note = s.error || "something went wrong"; return }
                if (s.saved !== undefined) {
                    win.note = "saved " + s.saved
                    return
                }
                win.srcFrames = s.frames || 1
                win.animated = !!s.animated
                win.note = s.cols + "×" + s.rows + " characters" +
                           (s.animated ? "  ·  " + s.frames + " frames" : "") +
                           "  ·  from " + s.src_w + "×" + s.src_h
                preview.source = ""
                preview.source = "preview.png?v=" + s.seq
            }
            x.send()
        }
    }

    FileDialog {
        id: openDlg
        title: "Pick a picture, gif or video"
        nameFilters: ["Images and video (*.png *.jpg *.jpeg *.webp *.bmp *.gif *.mp4 *.webm *.mkv *.mov)",
                      "Everything (*)"]
        onAccepted: {
            win.inputPath = selectedFile.toString().replace("file://", "")
            win.frameNo = 0
            win.push({})
        }
    }

    FileDialog {
        id: saveDlg
        property string fmt: "png"
        fileMode: FileDialog.SaveFile
        title: "Save as"
        onAccepted: {
            var p = selectedFile.toString().replace("file://", "")
            if (p.indexOf(".") < 0) p += "." + fmt
            win.note = "working…"
            win.push({ export_path: p })
        }
    }

    // ── layout ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // preview
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: panel
            border.color: stroke
            radius: 3

            Image {
                id: preview
                anchors.fill: parent
                anchors.margins: 10
                fillMode: Image.PreserveAspectFit
                smooth: false
                cache: false
                visible: win.inputPath !== ""
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: win.inputPath === ""
                spacing: 10
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "▟▛▜▙"
                    color: win.accent
                    font.pixelSize: 44
                    font.family: "monospace"
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "drop a picture, gif or video here"
                    color: win.dim
                    font.family: "monospace"
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Browse"
                    onClicked: openDlg.open()
                }
            }

            Rectangle {                          // busy tick
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 8
                width: 8; height: 8; radius: 4
                color: win.accent
                opacity: win.busy ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            DropArea {
                anchors.fill: parent
                onDropped: function (drop) {
                    if (!drop.hasUrls) return
                    win.inputPath = drop.urls[0].toString().replace("file://", "")
                    win.frameNo = 0
                    win.push({})
                }
            }
        }

        // controls
        Rectangle {
            Layout.preferredWidth: 330
            Layout.fillHeight: true
            color: panel
            border.color: stroke
            radius: 3

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "b i t e g l y p h"
                    color: win.accent
                    font.family: "monospace"
                    font.pixelSize: 17
                    font.letterSpacing: 2
                }
                Text {
                    text: win.inputPath ? win.inputPath.split("/").pop() : "nothing loaded"
                    color: win.dim
                    font.family: "monospace"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }

                Button {
                    Layout.fillWidth: true
                    text: "Open a file…"
                    onClicked: openDlg.open()
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }

                GridLayout {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 8
                    Layout.fillWidth: true

                    Text { text: "width"; color: win.dim; font.family: "monospace" }
                    RowLayout {
                        Layout.fillWidth: true
                        Slider {
                            Layout.fillWidth: true
                            from: 20; to: 300; stepSize: 2
                            value: win.cols
                            onMoved: { win.cols = Math.round(value); win.queue() }
                        }
                        Text {
                            text: win.cols
                            color: win.accent
                            font.family: "monospace"
                            Layout.preferredWidth: 30
                        }
                    }

                    Text { text: "charset"; color: win.dim; font.family: "monospace" }
                    ComboBox {
                        Layout.fillWidth: true
                        model: ["ascii", "blocks", "dense", "minimal", "solid", "bite"]
                        currentIndex: 0
                        onActivated: { win.charset = currentText; win.push({}) }
                    }

                    Text { text: "contrast"; color: win.dim; font.family: "monospace" }
                    Slider {
                        Layout.fillWidth: true
                        from: 0.4; to: 2.5; value: 1.0
                        onMoved: { win.contrast = value; win.queue() }
                    }

                    Text { text: "background"; color: win.dim; font.family: "monospace" }
                    ComboBox {
                        Layout.fillWidth: true
                        model: ["keep", "auto", "alpha", "flat colour", "photo"]
                        onActivated: {
                            win.cut = ["off", "auto", "alpha", "flood", "grabcut"][currentIndex]
                            win.push({})
                        }
                    }

                    Text { text: "colour"; color: win.dim; font.family: "monospace" }
                    Switch {
                        checked: true
                        onToggled: { win.colour = checked; win.push({}) }
                    }

                    Text { text: "invert"; color: win.dim; font.family: "monospace" }
                    Switch {
                        onToggled: { win.invert = checked; win.push({}) }
                    }

                    Text { text: "cut-out png"; color: win.dim; font.family: "monospace" }
                    Switch {
                        onToggled: { win.transparent = checked }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: win.animated
                    Text { text: "frame"; color: win.dim; font.family: "monospace" }
                    Slider {
                        Layout.fillWidth: true
                        from: 0; to: Math.max(0, win.srcFrames - 1); stepSize: 1
                        onMoved: { win.frameNo = Math.round(value); win.queue() }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }

                Text {
                    text: "save as"
                    color: win.dim
                    font.family: "monospace"
                    font.pixelSize: 11
                }
                GridLayout {
                    columns: 3
                    Layout.fillWidth: true
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: [["png", "still"], ["mp4", "video"], ["gif", "loop"],
                                ["txt", "text"], ["cast", "replay"]]
                        Button {
                            Layout.fillWidth: true
                            enabled: win.inputPath !== ""
                            text: modelData[0]
                            ToolTip.visible: hovered
                            ToolTip.text: modelData[1]
                            onClicked: {
                                saveDlg.fmt = modelData[0]
                                saveDlg.currentFolder = "file://" + win.inputPath.substring(
                                    0, win.inputPath.lastIndexOf("/"))
                                saveDlg.open()
                            }
                        }
                    }
                }

                Button {
                    Layout.fillWidth: true
                    enabled: win.inputPath !== ""
                    text: "Use as fetch logo"
                    ToolTip.visible: hovered
                    ToolTip.text: "drops a png into ~/.config/glitch/icons so glitch-fetch rolls it"
                    onClicked: {
                        var base = win.inputPath.split("/").pop().replace(/\.[^.]+$/, "")
                        win.note = "working…"
                        win.push({ export_path: "~/.config/glitch/icons/ascii-" + base + ".png",
                                   transparent: true })
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: win.note
                    color: win.busy ? win.accent : win.dim
                    font.family: "monospace"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Tell the engine to stop when the window closes, so `run` can exit cleanly.
    onClosing: {
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify({ quit: true }))
    }
}
