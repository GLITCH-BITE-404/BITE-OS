// bitedig — search as a solar system.
//
// Fullscreen. Query on top, space beneath. Every engine is a planet: they drift
// while idle, swirl into orbit on a search, and turn the whole time. Click one
// to read what it found. ENTER runs the sequence and opens it for real.
//
// search.py does the digging. QML cannot start a process, so the two talk
// through this directory — the launcher cd's here, hence relative paths.

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "bitedig"
    color: "#03060c"

    // one type scale and one spacing scale, used everywhere
    readonly property int  s1: 6
    readonly property int  s2: 12
    readonly property int  s3: 20
    readonly property int  s4: 34
    readonly property color ink:    "#dceee4"
    readonly property color inkDim: "#7e948a"
    readonly property color inkFar: "#41544c"
    readonly property color line:   "#132720"
    readonly property color accent: "#00e676"

    property string phase: "idle"          // idle · searching · orbit · detail · entering
    property int  seq: 0
    property int  lastSeen: -1
    property var  engines: []
    property var  results: ({})
    property int  selected: -1
    property string note: ""
    property string root: "~"
    property bool searxConfigured: false
    property int  focusIdx: 0        // keyboard-focused planet
    property int  resIdx: 0          // keyboard-focused result row

    readonly property var planets: [
        { id:"names",      label:"FILES",      engine:"fd",         depth:"names",
          hue:"#00e676", size:1.00, ring:false, tilt:  8, blurb:"names on your disk" },
        { id:"contents",   label:"INSIDE",     engine:"ripgrep",    depth:"contents",
          hue:"#2dd4bf", size:0.84, ring:true,  tilt:-14, blurb:"text within files" },
        { id:"media",      label:"MEDIA",      engine:"ffprobe",    depth:"media",
          hue:"#a78bfa", size:0.76, ring:false, tilt: 20, blurb:"pictures, audio, video" },
        { id:"duckduckgo", label:"DUCKDUCKGO", engine:"duckduckgo", depth:"web",
          hue:"#fb923c", size:0.94, ring:true,  tilt:-22, blurb:"the open web" },
        { id:"wikipedia",  label:"WIKIPEDIA",  engine:"wikipedia",  depth:"web",
          hue:"#e2e8f0", size:0.70, ring:false, tilt: 12, blurb:"encyclopaedia" },
        { id:"searx",      label:"SEARX",      engine:"searx",      depth:"web",
          hue:"#38bdf8", size:0.66, ring:false, tilt:-6,  blurb:"your own instance" },
        { id:"onion",      label:"ONION",      engine:"tor",        depth:"onion",
          hue:"#ff6b6b", size:0.88, ring:true,  tilt: 26, blurb:"reachable over Tor" }
    ]

    function here(n) { return Qt.resolvedUrl(n).toString().replace("file://", "") }
    function send(b) {
        seq += 1; b.seq = seq
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify(b))
    }
    function depthReady(d) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].depth === d) return engines[i].ready
        return false
    }
    function depthPackages(d) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].depth === d) return engines[i].packages || []
        return []
    }
    function planetReady(p) {
        if (p.id === "searx") return searxConfigured && depthReady("web")
        return depthReady(p.depth)
    }
    // Keyboard navigation only ever lands on a planet you can actually use.
    function usableIdx() {
        var out = []
        for (var i = 0; i < planets.length; i++)
            if (planetReady(planets[i])) out.push(i)
        return out
    }
    function stepFocus(dir) {
        var u = usableIdx()
        if (!u.length) return
        var at = u.indexOf(focusIdx)
        if (at < 0) { focusIdx = u[0]; return }
        focusIdx = u[(at + dir + u.length) % u.length]
    }
    function openFocused() {
        if (!planetReady(planets[focusIdx])) return
        if (phase === "idle") return
        selected = focusIdx; resIdx = 0; phase = "detail"
    }
    function enterResult() {
        var p = selected >= 0 ? planets[selected] : null
        if (!p) return
        var h = hitsFor(p)
        if (!h.length) return
        var pick = h[Math.max(0, Math.min(resIdx, h.length - 1))]
        matrix.target = pick.url || pick.path || ""
        matrix.viaTor = !!pick.needs_tor
        matrix.start()
    }

    function hitsFor(p) {
        var b = results[p.depth]; if (!b) return []
        var all = b.hits || []
        if (p.depth !== "web") return all
        var out = []
        for (var i = 0; i < all.length; i++)
            if ((all[i].engine || "") === p.engine) out.push(all[i])
        return out
    }
    function dig() {
        if (!query.text) { note = "type something first"; shake.restart(); return }
        var ds = [], seen = {}
        for (var i = 0; i < planets.length; i++) {
            var p = planets[i]
            if (planetReady(p) && !seen[p.depth]) { ds.push(p.depth); seen[p.depth] = true }
        }
        if (!ds.length) { note = "no engines yet — install one below"; return }
        results = ({}); selected = -1; phase = "searching"
        note = "scanning " + ds.length + " systems"
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
                var s; try { s = JSON.parse(x.responseText) } catch (e) { return }
                if (s.seq === undefined || s.seq === win.lastSeen) return
                win.lastSeen = s.seq
                if (s.engines) win.engines = s.engines
                if (s.opened)    { win.note = "opened " + s.opened; return }
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
                    win.note = n + (n === 1 ? " result" : " results") + "  ·  " + s.took + "s"
                    win.phase = "orbit"
                }
            }
            x.send()
        }
    }

    // ── deep space ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#03060c" }
            GradientStop { position: 0.45; color: "#061019" }
            GradientStop { position: 1.00; color: "#02040a" }
        }
    }
    Item {
        anchors.fill: parent
        Repeater {
            model: 170
            delegate: Rectangle {
                readonly property real dep: 0.2 + Math.random() * 0.8
                width: dep < 0.55 ? 1 : 2; height: width; radius: width
                color: dep > 0.9 ? "#bff5dc" : "#ffffff"
                opacity: 0.06 + dep * 0.4
                y: Math.random() * win.height
                NumberAnimation on x {
                    loops: Animation.Infinite
                    from: -6; to: win.width + 6
                    duration: 30000 + Math.random() * 55000
                }
                SequentialAnimation on opacity {
                    running: dep > 0.85; loops: Animation.Infinite
                    NumberAnimation { to: 0.15; duration: 1400 + Math.random() * 2200 }
                    NumberAnimation { to: 0.55; duration: 1400 + Math.random() * 2200 }
                }
            }
        }
    }

    // ── header ───────────────────────────────────────────────────────────────
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 172
        z: 40

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(win.width * 0.58, 860)
            spacing: win.s2

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "B I T E D I G"
                color: win.accent
                font.family: "monospace"; font.pixelSize: 13
                font.letterSpacing: 9; font.bold: true
                opacity: 0.9
            }

            Rectangle {
                id: bar
                Layout.fillWidth: true
                height: 58
                radius: height / 2
                color: "#060d13"
                border.width: 1
                border.color: query.activeFocus ? win.accent : win.line

                Rectangle {                              // focus halo
                    anchors.centerIn: parent
                    width: parent.width + 14; height: parent.height + 14
                    radius: height / 2
                    color: "transparent"
                    border.color: win.accent; border.width: 1
                    opacity: query.activeFocus ? 0.18 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: win.s3; anchors.rightMargin: win.s1
                    spacing: win.s2

                    Text {
                        text: "⌕"; color: win.accent; font.pixelSize: 24
                        opacity: query.activeFocus ? 1 : 0.55
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    TextField {
                        id: query
                        Layout.fillWidth: true
                        background: null
                        color: win.ink
                        selectionColor: win.accent
                        selectedTextColor: "#03060c"
                        placeholderText: "search everything"
                        placeholderTextColor: win.inkFar
                        font.family: "monospace"; font.pixelSize: 18
                        onAccepted: win.dig()
                        focus: true
                    }
                    Rectangle {
                        Layout.preferredWidth: 92; Layout.preferredHeight: 42
                        radius: 21
                        color: digMouse.containsMouse ? win.accent : "transparent"
                        border.color: win.accent; border.width: 1
                        opacity: win.phase === "searching" ? 0.4 : 1
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Text {
                            anchors.centerIn: parent
                            text: win.phase === "searching" ? "···" : "DIG"
                            color: digMouse.containsMouse ? "#03060c" : win.accent
                            font.family: "monospace"; font.pixelSize: 13
                            font.bold: true; font.letterSpacing: 2
                        }
                        MouseArea {
                            id: digMouse
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: win.phase !== "searching"
                            onClicked: win.dig()
                        }
                    }
                }

                SequentialAnimation on x {
                    id: shake; running: false
                    NumberAnimation { to: bar.x - 7; duration: 55 }
                    NumberAnimation { to: bar.x + 7; duration: 55 }
                    NumberAnimation { to: bar.x;     duration: 55 }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: win.note || (win.phase === "idle"
                      ? "each planet is a different engine"
                      : "")
                color: win.phase === "searching" ? win.accent : win.inkFar
                font.family: "monospace"; font.pixelSize: 11; font.letterSpacing: 0.6
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }
    }

    // ── space ────────────────────────────────────────────────────────────────
    Item {
        id: space
        anchors { top: header.bottom; left: parent.left
                  right: parent.right; bottom: parent.bottom
                  bottomMargin: 34 }        // keep labels off the hint line
        clip: true
        property real cx: width / 2
        property real cy: height / 2 - 44
        property real rx: Math.min(width * 0.36, 470)
        // Clamped so the bottom planet's label still fits above the edge.
        property real ry: Math.min(rx * 0.44, (height / 2) - 150)

        // orbit path, drawn once the planets take their places
        Repeater {
            model: 3
            delegate: Rectangle {
                anchors.centerIn: parent
                width:  space.rx * 2 * (0.72 + index * 0.16)
                height: space.ry * 2 * (0.72 + index * 0.16)
                y: space.cy - space.cy
                radius: width / 2
                color: "transparent"
                border.color: win.accent
                border.width: 1
                opacity: (win.phase === "orbit" || win.phase === "detail") ? 0.05 : 0
                Behavior on opacity { NumberAnimation { duration: 900 } }
                transform: Translate { y: space.cy - space.height / 2 }
            }
        }

        Repeater {
            model: win.planets
            delegate: Item {
                id: pl
                property var p: modelData
                property bool ready: win.planetReady(p)
                property var hits: win.hitsFor(p)
                property bool isSel: win.selected === index
                property real d: 104 * p.size

                width: d; height: d
                z: isSel ? 20 : 10

                property real ang: (index / win.planets.length) * 2 * Math.PI - Math.PI / 2
                property real orbX: space.cx + Math.cos(ang) * space.rx - d / 2
                property real orbY: space.cy + Math.sin(ang) * space.ry - d / 2
                // A planet is not just the globe: the label block under it runs
                // another ~72px. Spreading lanes to 84% of the height put that
                // text past the clip edge, so the bottom ones looked chopped.
                readonly property real labelRoom: 78
                readonly property real laneTop: 12
                readonly property real laneBot: Math.max(laneTop,
                                                space.height - d - labelRoom)
                property real lane: laneTop + (laneBot - laneTop) *
                                    (index / Math.max(1, win.planets.length - 1))

                states: [
                    State {
                        name: "orbit"
                        when: win.phase === "orbit" || win.phase === "searching"
                        PropertyChanges { target: pl; x: orbX; y: orbY; scale: 1; opacity: 1 }
                    },
                    State {
                        name: "detail"
                        when: win.phase === "detail" || win.phase === "entering"
                        PropertyChanges {
                            target: pl
                            x: isSel ? space.width * 0.24 - d : orbX
                            y: isSel ? space.cy - d : orbY
                            scale: isSel ? 2.0 : 0.34
                            opacity: isSel ? 1 : 0.14
                        }
                    }
                ]
                transitions: Transition {
                    NumberAnimation {
                        properties: "x,y,scale,opacity"
                        duration: 1000
                        easing.type: Easing.OutBack; easing.overshoot: 0.55
                    }
                }

                SequentialAnimation on x {
                    running: win.phase === "idle"; loops: Animation.Infinite
                    NumberAnimation {
                        from: -pl.d * 1.4; to: space.width + pl.d * 1.4
                        duration: 34000 + index * 6000
                    }
                }
                Binding { target: pl; property: "y"; value: pl.lane; when: win.phase === "idle" }

                Item {
                    id: globe
                    anchors.centerIn: parent
                    width: pl.d; height: pl.d
                    opacity: pl.ready ? 1 : 0.26
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Rectangle {                          // keyboard focus ring
                        visible: win.focusIdx === index && win.phase !== "idle"
                                 && win.phase !== "entering"
                        anchors.centerIn: parent
                        width: parent.width * 1.62; height: width; radius: width / 2
                        color: "transparent"
                        border.color: pl.p.hue; border.width: 2
                        opacity: 0.85
                        SequentialAnimation on scale {
                            running: win.focusIdx === index
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.06; duration: 780
                                              easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.00; duration: 780
                                              easing.type: Easing.InOutQuad }
                        }
                    }

                    Rectangle {                          // atmosphere
                        anchors.centerIn: parent
                        width: parent.width * 1.42; height: width; radius: width / 2
                        color: pl.p.hue
                        opacity: pl.isSel ? 0.16 : (hov.containsMouse ? 0.12 : 0.06)
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                    }

                    Rectangle {                          // body
                        id: sphere
                        anchors.fill: parent
                        radius: width / 2
                        clip: true
                        color: "#04070b"
                        border.color: pl.p.hue
                        border.width: pl.isSel ? 2 : 1

                        Item {                           // rotating bands = spin
                            anchors.fill: parent
                            NumberAnimation on rotation {
                                running: true; loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 14000 + index * 3600
                            }
                            Repeater {
                                model: 9
                                delegate: Rectangle {
                                    width: sphere.width * 1.7
                                    height: sphere.height / 11
                                    x: -sphere.width * 0.35
                                    y: index * (sphere.height / 9)
                                    color: pl.p.hue
                                    opacity: index % 3 === 0 ? 0.26
                                           : (index % 2 === 0 ? 0.14 : 0.07)
                                }
                            }
                        }

                        Rectangle {                      // terminator
                            anchors.fill: parent; radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "#ffffff14" }
                                GradientStop { position: 0.38; color: "#00000000" }
                                GradientStop { position: 0.72; color: "#00000066" }
                                GradientStop { position: 1.00; color: "#000000d8" }
                            }
                        }
                    }

                    Rectangle {                          // ring
                        visible: pl.p.ring
                        anchors.centerIn: parent
                        width: parent.width * 1.9; height: parent.height * 0.30
                        radius: height / 2
                        color: "transparent"
                        border.color: pl.p.hue; border.width: 1
                        opacity: 0.45
                        rotation: pl.p.tilt
                    }

                    Rectangle {                          // count
                        visible: win.phase !== "idle" && pl.hits.length > 0
                        anchors { top: parent.top; right: parent.right; margins: -2 }
                        width: Math.max(24, cnt.width + 14); height: 24; radius: 12
                        color: "#04070b"
                        border.color: pl.p.hue; border.width: 1
                        Text {
                            id: cnt; anchors.centerIn: parent
                            text: pl.hits.length
                            color: pl.p.hue
                            font.family: "monospace"; font.pixelSize: 11; font.bold: true
                        }
                    }
                }

                Column {
                    anchors { top: globe.bottom; topMargin: win.s2
                              horizontalCenter: parent.horizontalCenter }
                    spacing: 3
                    opacity: win.phase === "entering" && !pl.isSel ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pl.p.label
                        color: pl.ready ? win.ink : win.inkFar
                        font.family: "monospace"; font.pixelSize: 11
                        font.letterSpacing: 2; font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pl.ready ? pl.p.blurb : "needs " + win.depthPackages(pl.p.depth).join(" ")
                        color: pl.ready ? win.inkFar : "#c98a2e"
                        font.family: "monospace"; font.pixelSize: 9
                    }
                    Rectangle {
                        visible: !pl.ready && pl.p.id !== "searx"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 66; height: 22; radius: 11
                        color: ins.containsMouse ? "#c98a2e" : "transparent"
                        border.color: "#c98a2e"; border.width: 1
                        Text {
                            anchors.centerIn: parent; text: "install"
                            color: ins.containsMouse ? "#03060c" : "#c98a2e"
                            font.family: "monospace"; font.pixelSize: 9
                        }
                        MouseArea {
                            id: ins; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win.note = "installing " + win.depthPackages(pl.p.depth).join(" ")
                                win.send({ action:"install", packages: win.depthPackages(pl.p.depth) })
                            }
                        }
                    }
                }

                MouseArea {
                    id: hov
                    anchors.fill: globe
                    hoverEnabled: true
                    cursorShape: pl.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: globe.scale = 1.10
                    onExited:  globe.scale = 1.00
                    onClicked: {
                        if (!pl.ready) return
                        if (win.phase === "idle") { query.forceActiveFocus(); return }
                        win.selected = index; win.phase = "detail"
                    }
                }
                Behavior on scale { NumberAnimation { duration: 180 } }
            }
        }

        Rectangle {                                       // scan sweep
            visible: win.phase === "searching"
            width: 1; height: space.height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00e67600" }
                GradientStop { position: 0.5; color: "#00e676" }
                GradientStop { position: 1.0; color: "#00e67600" }
            }
            opacity: 0.6
            NumberAnimation on x {
                running: win.phase === "searching"; loops: Animation.Infinite
                from: 0; to: space.width; duration: 1500
            }
        }
    }

    // ── result panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: detail
        z: 30
        anchors { right: parent.right; top: header.bottom; bottom: parent.bottom }
        width: Math.min(win.width * 0.40, 640)
        color: "#040910"
        visible: opacity > 0.01
        opacity: (win.phase === "detail" || win.phase === "entering") ? 1 : 0
        x: (win.phase === "detail" || win.phase === "entering") ? win.width - width : win.width
        Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 320 } }

        property var p: win.selected >= 0 ? win.planets[win.selected] : null
        property var hits: p ? win.hitsFor(p) : []

        Rectangle { width: 1; height: parent.height; color: win.line }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: win.s4
            spacing: win.s3

            RowLayout {
                Layout.fillWidth: true
                spacing: win.s2
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: detail.p ? detail.p.hue : "#fff"
                }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: detail.p ? detail.p.label : ""
                        color: win.ink
                        font.family: "monospace"; font.pixelSize: 19
                        font.letterSpacing: 3; font.bold: true
                    }
                    Text {
                        text: detail.p ? detail.p.engine + " · " + detail.hits.length +
                              (detail.hits.length === 1 ? " result" : " results") : ""
                        color: win.inkFar
                        font.family: "monospace"; font.pixelSize: 10
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: cl.containsMouse ? win.line : "transparent"
                    border.color: win.line
                    Text { anchors.centerIn: parent; text: "✕"; color: win.inkDim
                           font.pixelSize: 12 }
                    MouseArea {
                        id: cl; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { win.phase = "orbit"; win.selected = -1 }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 46
                radius: 23
                color: ent.containsMouse ? (detail.p ? detail.p.hue : win.accent) : "transparent"
                border.color: detail.p ? detail.p.hue : win.accent
                border.width: 1
                opacity: detail.hits.length ? 1 : 0.3
                Behavior on color { ColorAnimation { duration: 180 } }
                Text {
                    anchors.centerIn: parent
                    text: "◈   E N T E R   T H I S   P L A N E T   ◈"
                    color: ent.containsMouse ? "#03060c" : (detail.p ? detail.p.hue : win.accent)
                    font.family: "monospace"; font.pixelSize: 11; font.bold: true
                }
                MouseArea {
                    id: ent
                    anchors.fill: parent; hoverEnabled: true
                    enabled: detail.hits.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var h = detail.hits[0]
                        matrix.target = h.url || h.path || ""
                        matrix.viaTor = !!h.needs_tor
                        matrix.start()
                    }
                }
            }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: detail.width - win.s4 * 2
                    spacing: win.s1
                    Repeater {
                        model: detail.hits
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: body.implicitHeight + win.s2 * 2
                            color: (rh.containsMouse || win.resIdx === index)
                                   ? "#07131a" : "transparent"
                            radius: 4
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Rectangle {                     // accent spine
                                width: 2; height: parent.height - 10
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                radius: 1
                                color: detail.p ? detail.p.hue : win.accent
                                opacity: (rh.containsMouse || win.resIdx === index)
                                         ? 0.95 : 0.25
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            Column {
                                id: body
                                x: win.s2; y: win.s2
                                width: parent.width - win.s2 * 2
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: modelData.title ? modelData.title
                                          : (modelData.name || modelData.path || "")
                                    color: win.ink
                                    font.family: "monospace"; font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    text: modelData.excerpt ? modelData.excerpt
                                          : (modelData.url || modelData.path || "")
                                    color: win.inkDim
                                    font.family: "monospace"; font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: !!modelData.url
                                    text: modelData.url || ""
                                    color: win.inkFar
                                    font.family: "monospace"; font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                }
                            }
                            MouseArea {
                                id: rh
                                anchors.fill: parent; hoverEnabled: true
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

    // ── entering ─────────────────────────────────────────────────────────────
    Item {
        id: matrix
        anchors.fill: parent
        z: 100
        visible: win.phase === "entering"
        property string target: ""
        property bool viaTor: false
        property real bloom: 0
        property real prog: 0

        function start() {
            if (!target) return
            bloom = 0; prog = 0
            win.phase = "entering"
            rain.reset(); seqAnim.restart()
        }

        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.95 }

        Canvas {
            id: rain
            anchors.fill: parent
            property var cols: []
            property int cell: 15
            function reset() {
                cols = []
                for (var i = 0; i < Math.ceil(width / cell); i++)
                    cols.push(-Math.random() * height)
            }
            Timer { running: matrix.visible; interval: 40; repeat: true
                    onTriggered: rain.requestPaint() }
            onPaint: {
                var c = getContext("2d")
                c.fillStyle = "rgba(0,0,0,0.09)"
                c.fillRect(0, 0, width, height)
                c.font = cell + "px monospace"
                var g = "01ABCDEF#*+=<>/\\|{}[]$%&@BITEOS"
                for (var i = 0; i < cols.length; i++) {
                    var x = i * cell, y = cols[i]
                    c.fillStyle = "rgba(200,255,225,0.95)"
                    c.fillText(g.charAt(Math.floor(Math.random() * g.length)), x, y)
                    c.fillStyle = "rgba(0,230,118,0.5)"
                    c.fillText(g.charAt(Math.floor(Math.random() * g.length)), x, y - cell)
                    c.fillStyle = "rgba(0,230,118,0.22)"
                    c.fillText(g.charAt(Math.floor(Math.random() * g.length)), x, y - cell * 2)
                    cols[i] = (y > height + Math.random() * 420) ? 0 : y + cell
                }
            }
        }

        Rectangle { anchors.fill: parent; color: win.accent; opacity: matrix.bloom * 0.92 }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: win.s3
            opacity: 1 - matrix.bloom
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: matrix.viaTor ? "R O U T I N G   T H R O U G H   T O R"
                                    : "E S T A B L I S H I N G   L I N K"
                color: "#c8ffe4"
                font.family: "monospace"; font.pixelSize: 20; font.letterSpacing: 3
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: win.width * 0.66
                text: matrix.target
                color: win.accent
                font.family: "monospace"; font.pixelSize: 12
                elide: Text.ElideMiddle
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 460; height: 2; color: "#0a1f16"
                Rectangle { height: parent.height; color: win.accent
                            width: parent.width * matrix.prog }
            }
            Text {
                id: phaseTxt
                Layout.alignment: Qt.AlignHCenter
                text: "handshake"
                color: win.inkFar
                font.family: "monospace"; font.pixelSize: 10; font.letterSpacing: 2
            }
        }

        SequentialAnimation {
            id: seqAnim
            NumberAnimation { target: matrix; property: "prog"; to: 0.34; duration: 720 }
            ScriptAction { script: phaseTxt.text = matrix.viaTor ? "building circuit"
                                                                 : "resolving host" }
            NumberAnimation { target: matrix; property: "prog"; to: 0.71; duration: 820 }
            ScriptAction { script: phaseTxt.text = "decrypting" }
            NumberAnimation { target: matrix; property: "prog"; to: 1.0; duration: 700 }
            ScriptAction { script: phaseTxt.text = "opening" }
            NumberAnimation { target: matrix; property: "bloom"; to: 1; duration: 620 }
            ScriptAction { script: win.send({ action:"open", target: matrix.target,
                                              tor: matrix.viaTor }) }
            PauseAnimation { duration: 420 }
            NumberAnimation { target: matrix; property: "bloom"; to: 0; duration: 520 }
            ScriptAction { script: win.phase = "detail" }
        }
    }

    Text {
        anchors { bottom: parent.bottom; left: parent.left; margins: win.s3 }
        z: 50
        text: win.phase === "detail"
              ? "↑↓ pick   ·   enter  open it   ·   ←/esc  back   ·   ctrl+q  quit"
              : (win.phase === "orbit"
                 ? "←→ or tab  pick a planet   ·   1-7 jump   ·   enter  open   ·   i  install   ·   /  search"
                 : "type and press enter   ·   ←→  planets   ·   i  install   ·   ctrl+q  quit")
        color: win.inkFar
        font.family: "monospace"; font.pixelSize: 10; font.letterSpacing: 1
        opacity: 0.65
    }

    // ── keyboard: the whole tool is driveable without a pointer ─────────────
    // This is not a nicety. A planets-and-clicking UI is unusable the moment a
    // touchpad dies, and a search tool is exactly what you reach for when
    // something is broken.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (e) {
            // typing in the box: let it through, except for the keys that steer
            if (query.activeFocus && e.key !== Qt.Key_Escape
                && e.key !== Qt.Key_Down && e.key !== Qt.Key_Tab) return

            if (win.phase === "detail") {
                var hs = win.selected >= 0 ? win.hitsFor(win.planets[win.selected]) : []
                if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    win.resIdx = Math.min(win.resIdx + 1, Math.max(0, hs.length - 1)); e.accepted = true
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    win.resIdx = Math.max(0, win.resIdx - 1); e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter
                           || e.key === Qt.Key_Space) {
                    win.enterResult(); e.accepted = true
                } else if (e.key === Qt.Key_Left) {
                    win.phase = "orbit"; win.selected = -1; e.accepted = true
                }
                return
            }

            if (win.phase === "orbit" || win.phase === "idle") {
                if (e.key === Qt.Key_Right || e.key === Qt.Key_L
                    || e.key === Qt.Key_Tab) { win.stepFocus(1);  e.accepted = true }
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_H
                         || e.key === Qt.Key_Backtab) { win.stepFocus(-1); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter
                         || e.key === Qt.Key_Space) {
                    if (win.phase === "orbit") { win.openFocused(); e.accepted = true }
                }
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_7) {
                    var i = e.key - Qt.Key_1
                    if (i < win.planets.length && win.planetReady(win.planets[i])) {
                        win.focusIdx = i
                        if (win.phase === "orbit") { win.selected = i; win.resIdx = 0
                                                     win.phase = "detail" }
                    }
                    e.accepted = true
                }
                else if (e.key === Qt.Key_I) {          // install the focused one
                    var fp = win.planets[win.focusIdx]
                    if (!win.planetReady(fp)) {
                        win.note = "installing " + win.depthPackages(fp.depth).join(" ")
                        win.send({ action:"install", packages: win.depthPackages(fp.depth) })
                    }
                    e.accepted = true
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: {
        if (win.phase === "detail") { win.phase = "orbit"; win.selected = -1 }
        else if (win.phase === "orbit") { win.phase = "idle"; win.results = ({}); win.note = "" }
        else Qt.quit()
    } }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "/"; onActivated: query.forceActiveFocus() }

    onClosing: {
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify({ quit: true }))
    }
}
