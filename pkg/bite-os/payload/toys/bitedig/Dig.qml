// bitedig — the window. search.py does the digging.
//
// Same split as biteglyph: QML cannot start a process, so the window writes
// request.json into this directory and the engine answers in status.json.
// The launcher cd's here first, hence the relative paths.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    width: 1240
    height: 780
    title: "bitedig"
    color: "#05070a"

    readonly property color accent: "#00e676"
    readonly property color warn:   "#ffb300"
    readonly property color danger: "#ff5252"
    readonly property color dim:    "#4d5f57"
    readonly property color panel:  "#0a0f13"
    readonly property color stroke: "#16241d"

    property int  seq: 0
    property int  lastSeen: -1
    property bool busy: false
    property string note: "pick your depths, then dig"
    property var engines: []
    property var results: ({})
    property string root: "~"

    // depth name -> chosen?
    property var picked: ({ names: true, contents: true, media: false,
                            web: false, onion: false })

    readonly property var depthInfo: [
        { id: "names",    label: "NAMES",    blurb: "file and folder names" },
        { id: "contents", label: "CONTENTS", blurb: "inside text files" },
        { id: "media",    label: "MEDIA",    blurb: "pictures, audio, video" },
        { id: "web",      label: "WEB",      blurb: "the open web" },
        { id: "onion",    label: "ONION",    blurb: "reachable over Tor" }
    ]

    function here(n) { return Qt.resolvedUrl(n).toString().replace("file://", "") }

    function send(body) {
        seq += 1
        body.seq = seq
        busy = true
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify(body))
    }

    function engineFor(id) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].depth === id) return engines[i]
        return null
    }

    function dig() {
        var ds = []
        for (var i = 0; i < depthInfo.length; i++) {
            var id = depthInfo[i].id
            if (picked[id]) ds.push(id)
        }
        if (!query.text || ds.length === 0) { note = "nothing to look for"; return }
        results = ({})
        note = "digging…"
        send({ q: query.text, depths: ds, root: root, limit: 40 })
    }

    Component.onCompleted: send({ action: "engines" })

    Timer {
        interval: 120; running: true; repeat: true
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
                if (s.engines) win.engines = s.engines
                if (s.opened) { win.note = "opened " + s.opened; return }
                if (s.installed) { win.note = "installed " + s.installed.join(" "); return }
                if (!s.ok) { win.note = s.error || "that did not work"; return }
                if (s.depths) {
                    win.results = s.depths
                    var n = 0
                    for (var k in s.depths) n += (s.depths[k].hits || []).length
                    win.note = n + " result" + (n === 1 ? "" : "s") + "  ·  " + s.took + "s"
                }
            }
            x.send()
        }
    }

    // ── warning before anything leaves the machine over Tor ──
    Dialog {
        id: torWarn
        property string url: ""
        anchors.centerIn: parent
        width: 520
        modal: true
        title: "Open over Tor?"
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: win.send({ action: "open", target: url, tor: true })
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: "#d7e3dc"
                font.family: "monospace"; font.pixelSize: 12
                text: "This opens in Tor Browser, routed through the Tor network.\n\n" +
                      "Tor is legitimate privacy software — journalists and people " +
                      "under censorship rely on it. It is also slow, and it does not " +
                      "make you anonymous on its own.\n\nOpening: " + torWarn.url
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: win.warn
                font.family: "monospace"; font.pixelSize: 11
                visible: { var e = win.engineFor("onion"); return e && !e.ready }
                text: "Tor is not installed yet — you will be asked to install it."
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // ── left: the depths, as orbits ──
        Rectangle {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            color: panel; border.color: stroke; radius: 3

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 10

                Text {
                    text: "b i t e d i g"
                    color: win.accent; font.family: "monospace"
                    font.pixelSize: 17; font.letterSpacing: 2
                }
                Text {
                    text: "each depth is a different engine"
                    color: win.dim; font.family: "monospace"; font.pixelSize: 10
                }

                Repeater {
                    model: win.depthInfo
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 62
                        radius: 3
                        property var eng: win.engineFor(modelData.id)
                        property bool ready: eng ? eng.ready : true
                        property bool on: win.picked[modelData.id] === true
                        color: on ? "#0f1b16" : "transparent"
                        border.color: on ? win.accent : win.stroke

                        // the "planet"
                        Rectangle {
                            id: orb
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 8
                            color: !parent.ready ? win.danger
                                                 : (parent.on ? win.accent : win.dim)
                            opacity: parent.on ? 1 : 0.55
                            SequentialAnimation on scale {
                                running: win.busy && parent.on
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.35; duration: 420 }
                                NumberAnimation { to: 1.0;  duration: 420 }
                            }
                        }
                        Rectangle {              // its orbit ring
                            anchors.centerIn: orb
                            width: 34; height: 34; radius: 17
                            color: "transparent"
                            border.color: orb.color
                            border.width: 1
                            opacity: 0.28
                            RotationAnimation on rotation {
                                running: win.busy; loops: Animation.Infinite
                                from: 0; to: 360; duration: 3200
                            }
                        }

                        Column {
                            x: 48; anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: parent.parent.on ? "#dff3e8" : win.dim
                                font.family: "monospace"; font.pixelSize: 12
                                font.letterSpacing: 1
                            }
                            Text {
                                text: modelData.blurb
                                color: win.dim; font.family: "monospace"; font.pixelSize: 9
                            }
                            Text {
                                visible: !parent.parent.parent.ready
                                text: "needs " + (parent.parent.parent.eng
                                      ? parent.parent.parent.eng.packages.join(" ") : "")
                                color: win.warn
                                font.family: "monospace"; font.pixelSize: 9
                            }
                        }

                        Button {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: 8
                            visible: !parent.ready
                            text: "get"
                            onClicked: {
                                win.note = "installing…"
                                win.send({ action: "install",
                                           packages: parent.eng ? parent.eng.packages : [] })
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: parent.ready ? 0 : 60
                            onClicked: {
                                var p = win.picked
                                p[modelData.id] = !p[modelData.id]
                                win.picked = p
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Text { text: "search from"; color: win.dim
                       font.family: "monospace"; font.pixelSize: 10 }
                TextField {
                    Layout.fillWidth: true
                    text: win.root
                    font.family: "monospace"; font.pixelSize: 11
                    onEditingFinished: win.root = text
                }
                Text {
                    Layout.fillWidth: true
                    text: win.note
                    color: win.busy ? win.accent : win.dim
                    font.family: "monospace"; font.pixelSize: 10
                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                }
            }
        }

        // ── right: query + results ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: query
                    Layout.fillWidth: true
                    placeholderText: "what are you looking for"
                    font.family: "monospace"; font.pixelSize: 15
                    onAccepted: win.dig()
                }
                Button { text: "DIG"; onClicked: win.dig() }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: panel; border.color: stroke; radius: 3

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: win.depthInfo
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                property var block: win.results[modelData.id]
                                property var hits: block ? (block.hits || []) : []
                                visible: hits.length > 0

                                Text {
                                    text: "▎" + modelData.label + "  " + hits.length
                                    color: win.accent
                                    font.family: "monospace"; font.pixelSize: 11
                                    font.letterSpacing: 1
                                    topPadding: 8
                                }

                                Repeater {
                                    model: hits
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: row.implicitHeight + 10
                                        color: ma.containsMouse ? "#101a15" : "transparent"
                                        radius: 2

                                        Column {
                                            id: row
                                            x: 10; y: 5
                                            width: parent.width - 20
                                            spacing: 1
                                            Text {
                                                width: parent.width
                                                text: modelData.title
                                                      ? modelData.title
                                                      : (modelData.name || modelData.path || "")
                                                color: "#cfe6d9"
                                                font.family: "monospace"; font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                width: parent.width
                                                visible: text !== ""
                                                text: modelData.url ? modelData.url
                                                      : (modelData.excerpt ? modelData.excerpt
                                                      : (modelData.path || ""))
                                                color: win.dim
                                                font.family: "monospace"; font.pixelSize: 10
                                                elide: Text.ElideMiddle
                                            }
                                        }

                                        MouseArea {
                                            id: ma
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                var t = modelData.url || modelData.path
                                                if (!t) return
                                                if (modelData.needs_tor) {
                                                    torWarn.url = t
                                                    torWarn.open()
                                                } else {
                                                    win.send({ action: "open", target: t })
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: Object.keys(win.results).length === 0
                            text: "\n  nothing yet — type something and press DIG\n\n" +
                                  "  a depth with a red planet needs its engine installed;\n" +
                                  "  press 'get' next to it and it will ask for your password"
                            color: win.dim
                            font.family: "monospace"; font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    onClosing: {
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify({ quit: true }))
    }
}
