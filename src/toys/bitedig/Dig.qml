// bitedig — search as a solar system.
//
// Fullscreen. Query goes in at the top; space is underneath. Each planet is a
// search engine. Idle, they drift past. Search, and they swirl into orbit with
// their result counts. Click one to see what it found; ENTER THIS PLANET runs
// the matrix sequence and opens it for real.
//
// search.py does the digging — QML cannot start a process, so the two talk
// through this directory. The launcher cd's here, hence the relative paths.

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "bitedig"
    color: "#02040a"

    readonly property color accent: "#00e676"
    readonly property color cyan:   "#22d3ee"
    readonly property color warn:   "#ffb300"
    readonly property color dim:    "#3d4d46"

    // idle · searching · orbit · detail · entering
    property string phase: "idle"
    property int  seq: 0
    property int  lastSeen: -1
    property var  engines: []
    property var  results: ({})
    property int  selected: -1
    property string note: ""
    property string root: "~"

    // Each planet is one engine. The web depth comes back tagged per engine, so
    // duckduckgo and wikipedia get their own worlds rather than sharing one.
    readonly property var planets: [
        { id:"names",      label:"FILES",      engine:"fd",         depth:"names",    hue:"#00e676", size:1.00, ring:false },
        { id:"contents",   label:"INSIDE",     engine:"ripgrep",    depth:"contents", hue:"#22d3ee", size:0.86, ring:true  },
        { id:"media",      label:"MEDIA",      engine:"ffprobe",    depth:"media",    hue:"#a78bfa", size:0.78, ring:false },
        { id:"duckduckgo", label:"DUCKDUCKGO", engine:"duckduckgo", depth:"web",      hue:"#f97316", size:0.92, ring:true  },
        { id:"wikipedia",  label:"WIKIPEDIA",  engine:"wikipedia",  depth:"web",      hue:"#e2e8f0", size:0.72, ring:false },
        { id:"searx",      label:"SEARX",      engine:"searx",      depth:"web",      hue:"#38bdf8", size:0.68, ring:false },
        { id:"onion",      label:"ONION",      engine:"tor",        depth:"onion",    hue:"#ff5252", size:0.88, ring:true  }
    ]

    function here(n) { return Qt.resolvedUrl(n).toString().replace("file://", "") }

    function send(body) {
        seq += 1
        body.seq = seq
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify(body))
    }

    function depthReady(depth) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].depth === depth) return engines[i].ready
        return false
    }
    function depthPackages(depth) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].depth === depth) return engines[i].packages || []
        return []
    }

    // A planet is alive if its depth's engine exists. searx only counts when
    // you have actually pointed it at an instance.
    function planetReady(p) {
        if (p.id === "searx") return searxConfigured && depthReady("web")
        return depthReady(p.depth)
    }
    property bool searxConfigured: false

    function hitsFor(p) {
        var block = results[p.depth]
        if (!block) return []
        var all = block.hits || []
        if (p.depth !== "web") return all
        var out = []
        for (var i = 0; i < all.length; i++)
            if ((all[i].engine || "") === p.engine) out.push(all[i])
        return out
    }

    function dig() {
        if (!query.text) { note = "type something first"; return }
        var ds = []
        var seen = {}
        for (var i = 0; i < planets.length; i++) {
            var p = planets[i]
            if (planetReady(p) && !seen[p.depth]) { ds.push(p.depth); seen[p.depth] = true }
        }
        if (ds.length === 0) { note = "no engines available — install one below"; return }
        results = ({})
        selected = -1
        phase = "searching"
        note = "scanning " + ds.length + " systems…"
        send({ q: query.text, depths: ds, root: root, limit: 40 })
    }

    Component.onCompleted: send({ action: "engines" })

    Timer {
        interval: 110; running: true; repeat: true
        onTriggered: {
            var x = new XMLHttpRequest()
            x.open("GET", "file://" + here("status.json"))
            x.onreadystatechange = function () {
                if (x.readyState !== XMLHttpRequest.DONE || !x.responseText) return
                var s
                try { s = JSON.parse(x.responseText) } catch (e) { return }
                if (s.seq === undefined || s.seq === win.lastSeen) return
                win.lastSeen = s.seq
                if (s.engines) win.engines = s.engines
                if (s.opened) { win.note = "opened " + s.opened; return }
                if (s.installed) { win.note = "installed " + s.installed.join(" "); return }
                if (!s.ok) {
                    win.note = s.error || "that did not work"
                    if (win.phase === "searching") win.phase = "idle"
                    return
                }
                if (s.depths) {
                    win.results = s.depths
                    var n = 0
                    for (var k in s.depths) n += (s.depths[k].hits || []).length
                    win.note = n + " result" + (n === 1 ? "" : "s") + " · " + s.took + "s"
                    win.phase = "orbit"
                }
            }
            x.send()
        }
    }

    // ── starfield ────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        Repeater {
            model: 140
            delegate: Rectangle {
                property real depthF: 0.25 + Math.random() * 0.75
                width: depthF < 0.5 ? 1 : 2
                height: width
                radius: width
                color: "#ffffff"
                opacity: 0.10 + depthF * 0.35
                y: Math.random() * win.height
                x: Math.random() * win.width
                NumberAnimation on x {
                    loops: Animation.Infinite
                    from: parent ? -10 : 0
                    to: win.width + 10
                    duration: 26000 + Math.random() * 40000
                }
            }
        }
        // a slow nebula wash so space is not flat black
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#02040a" }
                GradientStop { position: 0.55; color: "#050d14" }
                GradientStop { position: 1.0; color: "#02040a" }
            }
            opacity: 0.7
        }
    }

    // ── the search bar, always on top ────────────────────────────────────────
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 150
        z: 40

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(win.width * 0.62, 900)
            spacing: 10

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "b i t e d i g"
                color: win.accent
                font.family: "monospace"; font.pixelSize: 15; font.letterSpacing: 6
                opacity: 0.85
            }

            Rectangle {
                Layout.fillWidth: true
                height: 54
                radius: 27
                color: "#070d12"
                border.color: query.activeFocus ? win.accent : "#16241d"
                border.width: query.activeFocus ? 2 : 1

                Rectangle {                       // focus glow
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"
                    border.color: win.accent; border.width: 1
                    opacity: query.activeFocus ? 0.25 : 0
                    scale: query.activeFocus ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 220 } }
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22; anchors.rightMargin: 8
                    spacing: 10
                    Text {
                        text: "⌕"
                        color: win.accent; font.pixelSize: 22
                    }
                    TextField {
                        id: query
                        Layout.fillWidth: true
                        background: null
                        color: "#dff3e8"
                        placeholderText: "what are you looking for"
                        placeholderTextColor: win.dim
                        font.family: "monospace"; font.pixelSize: 17
                        onAccepted: win.dig()
                    }
                    Button {
                        text: win.phase === "searching" ? "…" : "DIG"
                        enabled: win.phase !== "searching"
                        onClicked: win.dig()
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: win.note
                color: win.phase === "searching" ? win.accent : win.dim
                font.family: "monospace"; font.pixelSize: 11
            }
        }
    }

    // ── space: the planets ───────────────────────────────────────────────────
    Item {
        id: space
        anchors { top: header.bottom; left: parent.left
                  right: parent.right; bottom: parent.bottom }
        clip: true

        property real cx: width / 2
        property real cy: height / 2 - 20
        property real orbitR: Math.min(width, height) * 0.33

        Repeater {
            id: planetRep
            model: win.planets

            delegate: Item {
                id: planetItem
                property var p: modelData
                property bool ready: win.planetReady(p)
                property var hits: win.hitsFor(p)
                property bool isSel: win.selected === index
                property real baseSize: 92 * p.size

                width: baseSize; height: baseSize

                // Idle: drift across space on your own lane.
                // Orbit: swirl into a ring around the centre.
                // Detail: the chosen one slides left, the rest shrink away.
                property real idleY: space.height * (0.18 + 0.64 * (index / (win.planets.length - 1)))
                property real ang: (index / win.planets.length) * 2 * Math.PI - Math.PI / 2
                property real orbX: space.cx + Math.cos(ang) * space.orbitR - baseSize / 2
                property real orbY: space.cy + Math.sin(ang) * space.orbitR * 0.62 - baseSize / 2

                states: [
                    State {
                        name: "orbit"; when: win.phase === "orbit" || win.phase === "searching"
                        PropertyChanges { target: planetItem; x: orbX; y: orbY; scale: 1; opacity: 1 }
                    },
                    State {
                        name: "detail"; when: win.phase === "detail" || win.phase === "entering"
                        PropertyChanges {
                            target: planetItem
                            x: isSel ? space.width * 0.22 - baseSize * 0.9 : orbX
                            y: isSel ? space.cy - baseSize * 0.9 : orbY
                            scale: isSel ? 1.8 : 0.42
                            opacity: isSel ? 1 : 0.20
                        }
                    }
                ]
                transitions: Transition {
                    NumberAnimation {
                        properties: "x,y,scale,opacity"
                        duration: 900; easing.type: Easing.OutBack; easing.overshoot: 0.7
                    }
                }

                // drifting, only while idle
                SequentialAnimation on x {
                    running: win.phase === "idle"
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -planetItem.baseSize
                        to: space.width + planetItem.baseSize
                        duration: 30000 + index * 5200
                    }
                }
                Binding {
                    target: planetItem; property: "y"
                    value: planetItem.idleY
                    when: win.phase === "idle"
                }

                // ── the planet itself ──
                Item {
                    id: body
                    anchors.centerIn: parent
                    width: planetItem.baseSize; height: planetItem.baseSize
                    opacity: planetItem.ready ? 1 : 0.30

                    Rectangle {                       // glow
                        anchors.centerIn: parent
                        width: parent.width * 1.5; height: parent.height * 1.5
                        radius: width / 2
                        color: planetItem.ready ? planetItem.p.hue : "#7a8a82"
                        opacity: planetItem.isSel ? 0.20 : 0.09
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }

                    Rectangle {                       // the sphere
                        id: sphere
                        anchors.fill: parent
                        radius: width / 2
                        clip: true
                        color: "#05080b"
                        border.color: planetItem.ready ? planetItem.p.hue : "#5c6b64"
                        border.width: planetItem.isSel ? 2 : 1

                        // banded surface, rotating — this is the spin
                        Item {
                            id: surface
                            anchors.fill: parent
                            NumberAnimation on rotation {
                                running: true; loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 9000 + index * 2400
                            }
                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    width: sphere.width * 1.6
                                    height: sphere.height / 9
                                    x: -sphere.width * 0.3
                                    y: index * (sphere.height / 7)
                                    color: planetItem.ready ? planetItem.p.hue : "#6b7a73"
                                    opacity: (index % 2 === 0) ? 0.20 : 0.09
                                }
                            }
                        }

                        // terminator, so it reads as a sphere and not a disc
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#00000000" }
                                GradientStop { position: 0.55; color: "#00000055" }
                                GradientStop { position: 1.0; color: "#000000cc" }
                            }
                        }
                    }

                    Rectangle {                       // ring
                        visible: planetItem.p.ring
                        anchors.centerIn: parent
                        width: parent.width * 1.75
                        height: parent.height * 0.34
                        radius: height / 2
                        color: "transparent"
                        border.color: planetItem.ready ? planetItem.p.hue : "#5c6b64"
                        border.width: 1
                        opacity: 0.55
                        rotation: -18
                    }

                    // result count badge
                    Rectangle {
                        visible: win.phase !== "idle" && planetItem.hits.length > 0
                        anchors { top: parent.top; right: parent.right }
                        width: Math.max(22, countTxt.width + 12); height: 22
                        radius: 11
                        color: "#05080b"
                        border.color: planetItem.p.hue
                        Text {
                            id: countTxt
                            anchors.centerIn: parent
                            text: planetItem.hits.length
                            color: planetItem.p.hue
                            font.family: "monospace"; font.pixelSize: 11; font.bold: true
                        }
                    }
                }

                // label under it
                Column {
                    anchors { top: body.bottom; topMargin: 8
                              horizontalCenter: parent.horizontalCenter }
                    spacing: 1
                    visible: win.phase !== "entering" || planetItem.isSel
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: planetItem.p.label
                        color: planetItem.ready ? "#cfe6d9" : "#5c6b64"
                        font.family: "monospace"; font.pixelSize: 10; font.letterSpacing: 1.5
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: planetItem.ready ? planetItem.p.engine
                                               : "needs " + win.depthPackages(planetItem.p.depth).join(" ")
                        color: planetItem.ready ? win.dim : win.warn
                        font.family: "monospace"; font.pixelSize: 9
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !planetItem.ready && planetItem.p.id !== "searx"
                        text: "install"
                        onClicked: {
                            win.note = "installing…"
                            win.send({ action: "install",
                                       packages: win.depthPackages(planetItem.p.depth) })
                        }
                    }
                }

                MouseArea {
                    anchors.fill: body
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: body.scale = 1.12
                    onExited: body.scale = 1.0
                    onClicked: {
                        if (!planetItem.ready) return
                        if (win.phase === "idle") { query.forceActiveFocus(); return }
                        win.selected = index
                        win.phase = "detail"
                    }
                    Behavior on scale { NumberAnimation { duration: 150 } }
                }
                Behavior on scale { NumberAnimation { duration: 150 } }
            }
        }

        // scanning sweep
        Rectangle {
            visible: win.phase === "searching"
            width: 2; height: space.height
            color: win.accent
            opacity: 0.5
            NumberAnimation on x {
                running: win.phase === "searching"
                loops: Animation.Infinite
                from: 0; to: space.width; duration: 1400
            }
        }
    }

    // ── result panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: detail
        z: 30
        anchors { right: parent.right; top: header.bottom; bottom: parent.bottom }
        width: Math.min(win.width * 0.42, 620)
        color: "#060a0ef2"
        border.color: "#16241d"
        visible: win.phase === "detail" || win.phase === "entering"
        opacity: visible ? 1 : 0
        x: visible ? win.width - width : win.width
        Behavior on x { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 300 } }

        property var p: win.selected >= 0 ? win.planets[win.selected] : null
        property var hits: p ? win.hitsFor(p) : []

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: detail.p ? detail.p.label : ""
                    color: detail.p ? detail.p.hue : "#fff"
                    font.family: "monospace"; font.pixelSize: 20; font.letterSpacing: 2
                }
                Item { Layout.fillWidth: true }
                Button { text: "✕"; onClicked: { win.phase = "orbit"; win.selected = -1 } }
            }
            Text {
                text: detail.p ? ("engine: " + detail.p.engine + "  ·  " +
                                  detail.hits.length + " result" +
                                  (detail.hits.length === 1 ? "" : "s")) : ""
                color: win.dim
                font.family: "monospace"; font.pixelSize: 11
            }

            Button {
                Layout.fillWidth: true
                enabled: detail.hits.length > 0
                text: "◈  ENTER THIS PLANET  ◈"
                onClicked: {
                    var h = detail.hits[0]
                    matrix.target = h.url || h.path || ""
                    matrix.viaTor = !!h.needs_tor
                    matrix.start()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#16241d" }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: detail.width - 44
                    spacing: 2
                    Repeater {
                        model: detail.hits
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: col.implicitHeight + 12
                            color: hov.containsMouse ? "#0e1a15" : "transparent"
                            radius: 2
                            Column {
                                id: col
                                x: 8; y: 6; width: parent.width - 16
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: modelData.title ? modelData.title
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
                                id: hov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    matrix.target = modelData.url || modelData.path || ""
                                    matrix.viaTor = !!modelData.needs_tor
                                    matrix.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── entering: the matrix sequence ────────────────────────────────────────
    Item {
        id: matrix
        anchors.fill: parent
        z: 100
        visible: win.phase === "entering"
        property string target: ""
        property bool viaTor: false
        property real bloom: 0

        function start() {
            if (!target) return
            bloom = 0
            win.phase = "entering"
            rain.reset()
            seqAnim.restart()
        }

        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.94 }

        Canvas {
            id: rain
            anchors.fill: parent
            property var cols: []
            property int cell: 16
            function reset() {
                cols = []
                var n = Math.ceil(width / cell)
                for (var i = 0; i < n; i++)
                    cols.push(-Math.random() * height)
            }
            Timer {
                running: matrix.visible; interval: 45; repeat: true
                onTriggered: rain.requestPaint()
            }
            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = "rgba(0,0,0,0.10)"
                ctx.fillRect(0, 0, width, height)
                ctx.font = cell + "px monospace"
                var glyphs = "01ABCDEF#*+=<>/\\|{}[]$%&@BITEOS"
                for (var i = 0; i < cols.length; i++) {
                    var ch = glyphs.charAt(Math.floor(Math.random() * glyphs.length))
                    var x = i * cell, y = cols[i]
                    ctx.fillStyle = "rgba(180,255,214,0.95)"
                    ctx.fillText(ch, x, y)
                    ctx.fillStyle = "rgba(0,230,118,0.55)"
                    ctx.fillText(glyphs.charAt(Math.floor(Math.random() * glyphs.length)),
                                 x, y - cell)
                    cols[i] = (y > height + Math.random() * 400) ? 0 : y + cell
                }
            }
        }

        // the LEDs coming on, then the web opening
        Rectangle {
            anchors.fill: parent
            color: win.accent
            opacity: matrix.bloom * 0.9
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 14
            opacity: 1 - matrix.bloom
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: matrix.viaTor ? "ROUTING THROUGH TOR" : "ESTABLISHING LINK"
                color: "#bdfad9"
                font.family: "monospace"; font.pixelSize: 22; font.letterSpacing: 5
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: matrix.target
                color: win.accent
                font.family: "monospace"; font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.maximumWidth: win.width * 0.7
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 420; height: 3; color: "#0b1f16"; radius: 2
                Rectangle {
                    height: parent.height; radius: 2; color: win.accent
                    width: parent.width * progress.value
                }
            }
            Text {
                id: phaseTxt
                Layout.alignment: Qt.AlignHCenter
                text: "handshake"
                color: win.dim
                font.family: "monospace"; font.pixelSize: 11
            }
        }

        QtObject { id: progress; property real value: 0 }

        SequentialAnimation {
            id: seqAnim
            NumberAnimation { target: progress; property: "value"
                              from: 0; to: 0.35; duration: 700 }
            ScriptAction { script: phaseTxt.text = matrix.viaTor ? "building circuit"
                                                                 : "resolving host" }
            NumberAnimation { target: progress; property: "value"
                              to: 0.72; duration: 800 }
            ScriptAction { script: phaseTxt.text = "decrypting" }
            NumberAnimation { target: progress; property: "value"
                              to: 1.0; duration: 700 }
            ScriptAction { script: phaseTxt.text = "opening" }
            NumberAnimation { target: matrix; property: "bloom"
                              from: 0; to: 1; duration: 620 }
            ScriptAction {
                script: {
                    win.send({ action: "open", target: matrix.target, tor: matrix.viaTor })
                }
            }
            PauseAnimation { duration: 420 }
            NumberAnimation { target: matrix; property: "bloom"
                              to: 0; duration: 500 }
            ScriptAction { script: { win.phase = "detail"; progress.value = 0 } }
        }
    }

    // ── keys ─────────────────────────────────────────────────────────────────
    Shortcut { sequence: "Escape"; onActivated: {
        if (win.phase === "detail") { win.phase = "orbit"; win.selected = -1 }
        else if (win.phase === "orbit") { win.phase = "idle"; win.results = ({}) }
        else Qt.quit()
    } }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "/"; onActivated: query.forceActiveFocus() }

    Text {
        anchors { bottom: parent.bottom; left: parent.left; margins: 14 }
        z: 50
        text: "Esc back · / search · Ctrl+Q quit"
        color: win.dim
        font.family: "monospace"; font.pixelSize: 10
        opacity: 0.7
    }

    onClosing: {
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify({ quit: true }))
    }
}
