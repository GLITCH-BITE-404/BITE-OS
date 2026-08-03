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
    property bool cinematics: true      // read from opts.json the launcher writes
    property bool flying: false         // mid fold-in — drives the shockwave
    property bool scatter: false        // one frame at the drift lanes, un-eased
    property int  focusIdx: 0        // keyboard-focused planet
    property int  resIdx: 0          // keyboard-focused result row

    readonly property var planets: [
        { id:"names",      label:"FILES",      engine:"fd",         depth:"names",
          hue:"#00e676", size:1.00, ring:false, tilt:  8, glyph:"◆",
          blurb:"names on your disk",
          good:"fastest way to find a file when you half-remember the name" },
        { id:"contents",   label:"INSIDE",     engine:"ripgrep",    depth:"contents",
          hue:"#2dd4bf", size:0.84, ring:true,  tilt:-14, glyph:"◈",
          blurb:"text within files",
          good:"when you remember a line but not which file it lives in" },
        { id:"media",      label:"MEDIA",      engine:"ffprobe",    depth:"media",
          hue:"#a78bfa", size:0.76, ring:false, tilt: 20, glyph:"▶",
          blurb:"pictures, audio, video",
          good:"finds media by name and reads the tags buried inside it" },
        { id:"duckduckgo", label:"DUCKDUCKGO", engine:"duckduckgo", depth:"web",
          hue:"#fb923c", size:0.94, ring:true,  tilt:-22, glyph:"◍",
          blurb:"the open web",
          good:"summaries and related topics, no tracking, no key needed" },
        { id:"wikipedia",  label:"WIKIPEDIA",  engine:"wikipedia",  depth:"web",
          hue:"#e2e8f0", size:0.70, ring:false, tilt: 12, glyph:"❋",
          blurb:"encyclopaedia",
          good:"straight to the article when you want the facts, not opinions" },
        { id:"searx",      label:"SEARX",      engine:"searx",      depth:"web",
          hue:"#38bdf8", size:0.66, ring:false, tilt:-6,  glyph:"⬡",
          blurb:"your own instance",
          good:"real aggregated results — point web_instance at your own Searx" },
        { id:"onion",      label:"ONION",      engine:"tor",        depth:"onion",
          hue:"#ff6b6b", size:0.88, ring:true,  tilt: 26, glyph:"☍",
          blurb:"reachable over Tor",
          good:"SecureDrop, Ahmia and archives — asks before anything leaves" }
    ]

    // Each planet keeps its own track and its own year, so nothing ever lines up.
    readonly property var orbitR:   [0.34, 0.52, 0.70, 0.86, 1.02, 1.16, 1.30]
    readonly property var orbitDur: [38000, 52000, 67000, 84000, 99000, 118000, 136000]
    readonly property var orbitPh:  [0.00, 0.37, 0.62, 0.15, 0.83, 0.48, 0.71]

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
    // Holding Enter fires onAccepted on key repeat, dozens of times a second.
    // One guard here is cheaper than making every downstream animation
    // re-entrant, which is what the runaway search bar actually was.
    property double lastDig: 0
    function dig() {
        var now = Date.now()
        if (now - lastDig < 700) return
        lastDig = now
        if (!query.text) { note = "type something first"; shake.restart(); return }
        var ds = [], seen = {}
        for (var i = 0; i < planets.length; i++) {
            var p = planets[i]
            if (planetReady(p) && !seen[p.depth]) { ds.push(p.depth); seen[p.depth] = true }
        }
        if (!ds.length) { note = "no engines yet — install one below"; return }
        results = ({}); selected = -1; phase = "searching"
        scatter = true; unscatter.restart()
        flying = true; flyTimer.restart()
        note = "scanning " + ds.length + " systems"
        send({ q: query.text, depths: ds, root: root, limit: 40 })
    }

    Timer { id: flyTimer;  interval: 840; onTriggered: win.flying = false }
    Timer { id: unscatter; interval: 40;  onTriggered: win.scatter = false }

    Component.onCompleted: {
        // QML cannot read environment variables, so the launcher drops the
        // settings next to us as json and we pick them up here.
        var o = new XMLHttpRequest()
        o.open("GET", "file://" + here("opts.json"))
        o.onreadystatechange = function () {
            if (o.readyState !== XMLHttpRequest.DONE || !o.responseText) return
            try {
                var j = JSON.parse(o.responseText)
                if (j.cinematics !== undefined) win.cinematics = !!j.cinematics
                if (j.searx) win.searxConfigured = true
                if (j.root) win.root = j.root
            } catch (e) {}
        }
        o.send()
        send({ action: "engines" })
    }

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
                    // Focus has to leave the text field or Left/Right just move
                    // the text cursor and the planets never hear them.
                    query.focus = false
                    keys.forceActiveFocus()
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
            model: 320
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

    // drifting movement lines — parallax streaks that sell the depth
    Item {
        anchors.fill: parent
        Repeater {
            model: 14
            delegate: Rectangle {
                readonly property real dep: 0.3 + Math.random() * 0.7
                width: 40 + Math.random() * 150
                height: 1
                y: Math.random() * win.height
                opacity: 0.05 + dep * 0.10
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 0.5; color: "#9fe8c4" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
                NumberAnimation on x {
                    loops: Animation.Infinite
                    from: -220; to: win.width + 220
                    duration: 9000 + Math.random() * 17000
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

                // Shake a transform, never x itself. Animating x to "bar.x ± 7"
                // reads bar.x while it is ALREADY mid-animation, so holding
                // Enter compounded the offset and walked the bar off screen.
                transform: Translate { id: shakeT }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 50 }
                    NumberAnimation { target: shakeT; property: "x"; to:  8; duration: 50 }
                    NumberAnimation { target: shakeT; property: "x"; to: -4; duration: 45 }
                    NumberAnimation { target: shakeT; property: "x"; to:  0; duration: 45 }
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
                  bottomMargin: 34 }
        clip: true

        property real cx: width / 2
        property real cy: height / 2 - 10
        // The system was cramped into a third of the screen, so every planet
        // piled onto the sun and the labels landed on each other.
        property real unit: Math.min(width * 0.34, height * 0.52)
        // How squashed the ellipses are. Derived, not fixed: on a short screen
        // a 0.52 flattening pushed the outermost planet's label past the
        // bottom edge. This keeps the whole system inside whatever room it has.
        property real flat: Math.max(0.26, Math.min(0.52,
                            (height / 2 + 10 - 130) / Math.max(1, unit * 1.30)))

        // orbits freeze while you are reading a card, so the popup does not
        // wander off the planet it belongs to
        property bool frozen: win.phase === "detail" || win.phase === "entering"
        property real selCX: width / 2
        property real selTop: height / 2

        // ── the sun ──
        Item {
            id: sun
            opacity: win.phase === "idle" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 700 } }
            x: space.cx - width / 2
            y: space.cy - height / 2
            width: 92; height: 92
            z: 5

            Repeater {                                   // corona
                model: 3
                delegate: Rectangle {
                    anchors.centerIn: parent
                    width: sun.width * (1.5 + index * 0.75)
                    height: width; radius: width / 2
                    color: "#ffcf5c"
                    opacity: 0.10 - index * 0.028
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.07; duration: 2400 + index * 700
                                          easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.00; duration: 2400 + index * 700
                                          easing.type: Easing.InOutSine }
                    }
                }
            }
            Rectangle {
                anchors.fill: parent; radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#fff3b0" }
                    GradientStop { position: 0.55; color: "#ffb020" }
                    GradientStop { position: 1.0; color: "#c05a00" }
                }
            }
            Item {                                       // surface churn
                anchors.fill: parent
                NumberAnimation on rotation {
                    loops: Animation.Infinite; from: 0; to: 360; duration: 46000
                }
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: sun.width * 1.4; height: sun.height * 0.07
                        x: -sun.width * 0.2
                        y: sun.height * (0.26 + index * 0.24)
                        color: "#7a3b00"; opacity: 0.22; radius: 4
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: "◉"; color: "#3a1c00"; font.pixelSize: 26; opacity: 0.35
            }
        }

        // shockwave when the system forms
        Rectangle {
            id: shockwave
            x: space.cx - width / 2
            y: space.cy - height / 2
            width: 40; height: 40; radius: width / 2
            color: "transparent"
            border.color: "#ffffff"; border.width: 2
            opacity: 0
            z: 3
            ParallelAnimation {
                running: win.flying
                NumberAnimation { target: shockwave; property: "width"
                                  from: 40; to: space.unit * 2.6; duration: 700 }
                NumberAnimation { target: shockwave; property: "height"
                                  from: 40; to: space.unit * 2.6 * space.flat; duration: 700 }
                SequentialAnimation {
                    NumberAnimation { target: shockwave; property: "opacity"
                                      from: 0; to: 0.45; duration: 120 }
                    NumberAnimation { target: shockwave; property: "opacity"
                                      to: 0; duration: 560 }
                }
            }
        }

        // ── decorative moons, close in and quick ──
        Repeater {
            model: 5
            delegate: Item {
                property real r: 78 + index * 17
                property real t: 0
                NumberAnimation on t {
                    running: !space.frozen && win.phase !== "idle"
                    loops: Animation.Infinite
                    from: 0; to: 1; duration: 7000 + index * 2600
                }
                opacity: win.phase === "idle" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 700 } }
                property real a: (t + index * 0.2) * 2 * Math.PI
                x: space.cx + Math.cos(a) * r - 3
                y: space.cy + Math.sin(a) * r * 0.42 - 3
                z: 4
                Rectangle {
                    width: 5; height: 5; radius: 3
                    color: "#ffd479"; opacity: 0.55
                }
            }
        }

        // ── one orbit line per planet ──
        Repeater {
            model: win.planets
            delegate: Rectangle {
                property real rr: space.unit * win.orbitR[index]
                x: space.cx - rr; y: space.cy - rr * space.flat
                width: rr * 2; height: rr * space.flat * 2
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: win.planetReady(modelData) ? modelData.hue : "#46545c"
                opacity: win.phase === "idle" ? 0
                       : (win.selected === index ? 0.30
                       : (win.planetReady(modelData) ? 0.13 : 0.06))
                Behavior on opacity { NumberAnimation { duration: 400 } }
                z: 1
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
                property real d: 96 * p.size
                z: isSel ? 20 : 10

                // ── orbital position ──
                property real rr: space.unit * win.orbitR[index]
                property real t: 0
                NumberAnimation on t {
                    running: !space.frozen
                    loops: Animation.Infinite
                    from: 0; to: 1; duration: win.orbitDur[index]
                }
                property real ang: (t + win.orbitPh[index]) * 2 * Math.PI
                property real orbX: space.cx + Math.cos(ang) * rr - d / 2
                property real orbY: space.cy + Math.sin(ang) * rr * space.flat - d / 2

                // Idle: they fly past, each on its own lane at its own speed.
                // Search: they fold into the system. That transition is the
                // best moment in the whole thing, so it gets its own easing.
                property real driftT: 0
                readonly property real phaseOff: Math.random()
                NumberAnimation on driftT {
                    running: win.phase === "idle"
                    loops: Animation.Infinite
                    from: 0; to: 1; duration: 26000 + Math.random() * 32000
                }
                readonly property var laneMix: [0.10, 0.46, 0.24, 0.70, 0.34, 0.86, 0.58]
                property real driftX: ((driftT + phaseOff) % 1.0)
                                      * (space.width + d * 2.2) - d * 1.1
                property real driftY: 16 + (space.height - d - 92) * laneMix[index % 7]

                // `scatter` throws them back out to their drift lanes with the
                // easing off, so the very next frame flies them in again. Without
                // it a second search moved nothing: they were already in orbit,
                // the position never changed, and no animation ever ran.
                x: (win.phase === "idle" || win.scatter) ? driftX : orbX
                y: (win.phase === "idle" || win.scatter) ? driftY : orbY
                // Fast in, hard stop — they should look flung into formation.
                Behavior on x {
                    enabled: win.phase !== "idle" && !win.scatter
                    NumberAnimation { duration: 780; easing.type: Easing.InOutQuart }
                }
                Behavior on y {
                    enabled: win.phase !== "idle" && !win.scatter
                    NumberAnimation { duration: 780; easing.type: Easing.InOutQuart }
                }

                // the card needs to know where its planet actually is
                Binding { target: space; property: "selCX"
                          value: pl.x + pl.d / 2; when: pl.isSel }
                Binding { target: space; property: "selTop"
                          value: pl.y; when: pl.isSel }

                // ── speed lines ──
                // Driven by MEASURED velocity, not by guessing the direction
                // from stale drift coordinates. That guess is why they ended up
                // floating in empty space at the wrong angle, detached from the
                // planet they were supposed to belong to.
                property real prevX: 0
                property real prevY: 0
                property real vx: 0
                property real vy: 0
                property real speed: Math.sqrt(vx * vx + vy * vy)
                Timer {
                    interval: 32; repeat: true; running: win.phase !== "entering"
                    onTriggered: {
                        pl.vx = pl.x - pl.prevX
                        pl.vy = pl.y - pl.prevY
                        pl.prevX = pl.x
                        pl.prevY = pl.y
                    }
                }

                Item {
                    anchors.centerIn: globe
                    width: 1; height: 1
                    z: -2
                    // point along travel; the streaks are drawn trailing behind
                    rotation: Math.atan2(pl.vy, pl.vx) * 180 / Math.PI
                    // Visible for the whole flight. Gating purely on measured
                    // speed hid them after ~150ms, because the old easing spent
                    // the rest of its time crawling.
                    opacity: win.flying ? Math.min(1, 0.3 + pl.speed / 12) : 0
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Repeater {
                        model: 6
                        delegate: Rectangle {
                            readonly property real off: (index - 2.5) * (pl.d * 0.16)
                            height: 2
                            width: pl.d * (0.7 + (index % 3) * 0.5)
                            radius: 1
                            x: -pl.d * 0.45 - width
                            y: off
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#ffffff00" }
                                GradientStop { position: 1.0; color: "#ffffff" }
                            }
                            opacity: 0.5 + (index % 3) * 0.18
                        }
                    }
                }

                Item {
                    id: globe
                    anchors.centerIn: parent
                    width: pl.d; height: pl.d
                    opacity: pl.ready ? 1 : 0.42
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
                        color: pl.ready ? pl.p.hue : "#4a565e"
                        opacity: pl.ready ? (pl.isSel ? 0.16
                                            : (hov.containsMouse ? 0.12 : 0.06))
                                          : 0.03
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                    }

                    Rectangle {                          // body
                        id: sphere
                        anchors.fill: parent
                        radius: width / 2
                        clip: true
                        color: pl.ready ? Qt.darker(pl.p.hue, 6.0) : "#0b1116"
                        border.color: pl.ready ? pl.p.hue : "#46545c"
                        border.width: pl.isSel ? 2 : 1

                        // Bands used to be hard stripes at 0.26 opacity, which
                        // read as a barcode rather than a surface. Soft, low and
                        // few, drifting rather than spinning hard.
                        Item {
                            anchors.fill: parent
                            NumberAnimation on rotation {
                                running: true; loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 22000 + index * 5200
                            }
                            Repeater {
                                model: 4
                                delegate: Rectangle {
                                    width: sphere.width * 1.8
                                    height: sphere.height * (0.07 + (index % 2) * 0.05)
                                    x: -sphere.width * 0.4
                                    y: sphere.height * (0.20 + index * 0.19)
                                    color: pl.ready ? pl.p.hue : "#6e7c84"
                                    opacity: index % 2 === 0 ? 0.13 : 0.07
                                }
                            }
                        }

                        // Round it: a soft lit limb top-left, deep shadow lower
                        // right. The old version put a white wash across the
                        // whole left edge, which bleached the colour to yellow.
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.00; color: "#ffffff10" }
                                GradientStop { position: 0.30; color: "#00000000" }
                                GradientStop { position: 1.00; color: "#00000070" }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "#00000000" }
                                GradientStop { position: 0.52; color: "#00000000" }
                                GradientStop { position: 1.00; color: "#000000b0" }
                            }
                        }
                    }

                    Rectangle {                          // ring
                        visible: pl.p.ring
                        anchors.centerIn: parent
                        width: parent.width * 1.9; height: parent.height * 0.30
                        radius: height / 2
                        color: "transparent"
                        border.color: pl.ready ? pl.p.hue : "#46545c"
                        border.width: 1
                        opacity: pl.ready ? 0.45 : 0.22
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

                Rectangle {                         // keeps a label readable when
                    anchors.fill: labelCol             // it drifts over a neighbour
                    anchors.margins: -6
                    radius: 5
                    color: "#03060cd0"
                    opacity: win.phase === "idle" ? 0 : 0.85
                    visible: win.phase !== "entering" || pl.isSel
                    z: -1
                }
                Column {
                    id: labelCol
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

    // ── the card, floating above whichever planet you picked ─────────────────
    Item {
        id: detail
        z: 60
        visible: opacity > 0.01
        opacity: (win.phase === "detail" || win.phase === "entering") ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        property var p: win.selected >= 0 ? win.planets[win.selected] : null
        property var hits: p ? win.hitsFor(p) : []
        readonly property int cw: 460
        readonly property int ch: Math.min(430, 176 + Math.max(1, hits.length) * 46)

        width: cw; height: ch
        // sit above the planet, but never off the edge of the screen
        x: Math.max(16, Math.min(win.width - cw - 16,
                    space.x + space.selCX - cw / 2))
        y: Math.max(header.height + 8,
                    space.y + space.selTop - ch - 18)
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "#050b11f5"
            border.color: detail.p ? detail.p.hue : win.accent
            border.width: 1
        }
        Rectangle {                                   // glow
            anchors.fill: parent; anchors.margins: -3
            radius: 13; color: "transparent"
            border.color: detail.p ? detail.p.hue : win.accent
            border.width: 1; opacity: 0.18
        }
        // little stem pointing down at the planet
        Rectangle {
            width: 10; height: 10; rotation: 45
            color: "#050b11"
            border.color: detail.p ? detail.p.hue : win.accent
            border.width: 1
            x: Math.max(14, Math.min(detail.cw - 24,
                        space.x + space.selCX - detail.x - 5))
            y: detail.ch - 5
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {                            // the engine's mark
                    width: 42; height: 42; radius: 8
                    color: "transparent"
                    border.color: detail.p ? detail.p.hue : win.accent
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: detail.p ? detail.p.glyph : "?"
                        color: detail.p ? detail.p.hue : win.accent
                        font.pixelSize: 20
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Text {
                        text: detail.p ? detail.p.label : ""
                        color: win.ink
                        font.family: "monospace"; font.pixelSize: 16
                        font.letterSpacing: 2; font.bold: true
                    }
                    Text {
                        text: detail.p ? (detail.p.engine + "  ·  " + detail.hits.length +
                              (detail.hits.length === 1 ? " result" : " results")) : ""
                        color: detail.p ? detail.p.hue : win.inkDim
                        font.family: "monospace"; font.pixelSize: 10
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "esc"
                    color: win.inkFar
                    font.family: "monospace"; font.pixelSize: 10
                }
            }

            Text {                                     // what it is good for
                Layout.fillWidth: true
                text: detail.p ? detail.p.good : ""
                color: win.inkFar
                font.family: "monospace"; font.pixelSize: 10
                wrapMode: Text.Wrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: detail.cw - 32
                    spacing: 2
                    Repeater {
                        model: detail.hits
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: rb.implicitHeight + 12
                            radius: 4
                            color: (rh.containsMouse || win.resIdx === index)
                                   ? "#0b1a22" : "transparent"
                            Rectangle {
                                width: 2; height: parent.height - 8; x: 0; radius: 1
                                anchors.verticalCenter: parent.verticalCenter
                                color: detail.p ? detail.p.hue : win.accent
                                opacity: (rh.containsMouse || win.resIdx === index) ? 1 : 0.2
                            }
                            Column {
                                id: rb
                                x: 10; y: 6; width: parent.width - 20; spacing: 2
                                Text {
                                    width: parent.width
                                    text: modelData.title ? modelData.title
                                          : (modelData.name || modelData.path || "")
                                    color: win.ink
                                    font.family: "monospace"; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    text: modelData.excerpt ? modelData.excerpt
                                          : (modelData.url || modelData.path || "")
                                    color: win.inkDim
                                    font.family: "monospace"; font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }
                            MouseArea {
                                id: rh
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.resIdx = index
                                    matrix.target = modelData.url || modelData.path || ""
                                    matrix.viaTor = !!modelData.needs_tor
                                    matrix.start()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 34; radius: 17
                color: ent.containsMouse ? (detail.p ? detail.p.hue : win.accent) : "transparent"
                border.color: detail.p ? detail.p.hue : win.accent
                opacity: detail.hits.length ? 1 : 0.3
                Text {
                    anchors.centerIn: parent
                    text: "◈  E N T E R  ◈"
                    color: ent.containsMouse ? "#03060c" : (detail.p ? detail.p.hue : win.accent)
                    font.family: "monospace"; font.pixelSize: 10; font.bold: true
                }
                MouseArea {
                    id: ent
                    anchors.fill: parent; hoverEnabled: true
                    enabled: detail.hits.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.enterResult()
                }
            }
        }
    }

    // ── entering: crash → break in → SUCCESS → the lights come up ───────────
    //
    // Four stages. It is deliberately theatrical, and deliberately skippable —
    // `cinematics=off` in the config drops straight to opening the thing, and
    // any key aborts mid-way. A five-second animation you cannot escape stops
    // being cool the third time you see it.
    Item {
        id: matrix
        anchors.fill: parent
        z: 100
        visible: win.phase === "entering"
        focus: visible

        property string target: ""
        property bool viaTor: false
        property int  stage: 0          // 0 crash · 1 break-in · 2 success · 3 lights
        property real bloom: 0
        property real glare: 1

        function start() {
            if (!target) return
            if (!win.cinematics) {           // straight to business
                win.send({ action: "open", target: target, tor: viaTor })
                win.note = "opening " + target
                return
            }
            stage = 0; bloom = 0; glare = 1
            feed.clear()
            win.phase = "entering"
            reel.restart()
        }
        function abort() {
            reel.stop(); flood.stop()
            win.phase = "detail"
        }
        Keys.onPressed: function (e) { matrix.abort(); e.accepted = true }

        Rectangle { anchors.fill: parent; color: "#000000" }

        // ── stage 1: the break-in, printed like a terminal ──
        ListModel { id: feed }
        Timer {
            id: flood
            interval: 55; repeat: true; running: matrix.stage === 1
            property int n: 0
            onTriggered: {
                var host = matrix.target.replace(/^https?:\/\//, "").split("/")[0]
                var hex = "0123456789abcdef"
                function h(k) { var o=""; for (var i=0;i<k;i++)
                    o += hex.charAt(Math.floor(Math.random()*16)); return o }
                var lines = [
                    "resolving " + host,
                    "route " + h(2) + "." + h(2) + "." + h(2) + "." + h(2) + " -> gw",
                    "handshake syn/ack  seq=0x" + h(8),
                    "negotiating cipher suite " + h(4),
                    "key exchange " + h(16),
                    matrix.viaTor ? "circuit hop " + (1 + matrix.stage) + "/3  relay=" + h(6)
                                  : "tls1.3  alpn=h2  sni=" + host,
                    "payload " + h(24),
                    "bypass " + h(4) + " :: " + h(4) + " :: " + h(4),
                    "injecting " + h(12),
                    "0x" + h(8) + "  " + h(8) + "  " + h(8) + "  " + h(8)
                ]
                feed.append({ line: lines[n % lines.length] })
                if (feed.count > 26) feed.remove(0)
                n += 1
            }
        }
        ListView {
            anchors.fill: parent
            anchors.margins: 44
            model: feed
            visible: matrix.stage === 1
            interactive: false
            delegate: Text {
                text: "> " + line
                color: index > feed.count - 4 ? "#c8ffe4" : "#00b85e"
                opacity: 0.35 + 0.65 * (index / Math.max(1, feed.count))
                font.family: "monospace"; font.pixelSize: 13
            }
        }
        // a dead machine flickers before it comes back
        Rectangle {
            anchors.fill: parent; color: "#000000"
            opacity: matrix.stage === 0 ? 1 : 0
            SequentialAnimation on opacity {
                running: matrix.stage === 0
                loops: 2
                NumberAnimation { to: 0.86; duration: 60 }
                NumberAnimation { to: 1.00; duration: 90 }
            }
        }

        // ── stage 2: SUCCESS ──
        Item {
            anchors.centerIn: parent
            visible: matrix.stage === 2
            Text {
                id: successTxt
                anchors.centerIn: parent
                text: "SUCCESS"
                color: "#00ff88"
                font.family: "monospace"; font.pixelSize: 84
                font.bold: true; font.letterSpacing: 16
                // brightness breathing, plus a slow float
                opacity: matrix.glare
                SequentialAnimation on scale {
                    running: matrix.stage === 2; loops: Animation.Infinite
                    NumberAnimation { to: 1.04; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.00; duration: 620; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: matrix.stage === 2; loops: Animation.Infinite
                    NumberAnimation { to: -10; duration: 1500; easing.type: Easing.InOutSine }
                    NumberAnimation { to:  10; duration: 1500; easing.type: Easing.InOutSine }
                }
            }
            Text {                                   // ghost behind it = glow
                anchors.centerIn: successTxt
                text: successTxt.text
                color: "#00ff88"
                font: successTxt.font
                opacity: matrix.glare * 0.30
                scale: successTxt.scale * 1.06
            }
            Text {
                anchors { top: successTxt.bottom; topMargin: 26
                          horizontalCenter: successTxt.horizontalCenter }
                text: matrix.viaTor ? "circuit established" : "link established"
                color: "#5f8f77"
                font.family: "monospace"; font.pixelSize: 13; font.letterSpacing: 4
            }
        }

        // ── stage 3: the LEDs come up, one by one, until the screen is the planet
        Grid {
            id: leds
            anchors.fill: parent
            visible: matrix.stage === 3
            columns: Math.max(1, Math.floor(win.width / 26))
            rows: Math.max(1, Math.floor(win.height / 26))
            property color lit: detail.p ? detail.p.hue : win.accent
            Repeater {
                model: leds.columns * leds.rows
                delegate: Rectangle {
                    width: win.width / leds.columns
                    height: win.height / leds.rows
                    color: leds.lit
                    // ripple outward from the middle, with a little scatter so it
                    // reads as lamps warming up rather than a wipe
                    property real cxi: (index % leds.columns) - leds.columns / 2
                    property real cyi: Math.floor(index / leds.columns) - leds.rows / 2
                    property real dist: Math.sqrt(cxi * cxi + cyi * cyi)
                    opacity: 0
                    NumberAnimation on opacity {
                        running: matrix.stage === 3
                        to: 1; duration: 420
                        easing.type: Easing.OutQuad
                    }
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Timer {
                        running: matrix.stage === 3
                        interval: dist * 34 + Math.random() * 260
                        repeat: false
                        onTriggered: parent.opacity = 1
                    }
                    Component.onCompleted: opacity = 0
                }
            }
        }
        Rectangle {                                   // final wash to white
            anchors.fill: parent
            color: "#ffffff"
            opacity: matrix.bloom
        }

        Text {
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                      bottomMargin: 26 }
            text: "any key to skip"
            color: "#33564a"
            font.family: "monospace"; font.pixelSize: 10
            visible: matrix.stage < 3
        }

        SequentialAnimation {
            id: reel
            // 1. the machine dies
            PauseAnimation { duration: 520 }
            ScriptAction { script: matrix.stage = 1 }
            // 2. breaking in
            PauseAnimation { duration: 2300 }
            ScriptAction { script: { matrix.stage = 2; matrix.glare = 1 } }
            // 3. SUCCESS, brightness swelling
            SequentialAnimation {
                loops: 3
                NumberAnimation { target: matrix; property: "glare"
                                  to: 0.45; duration: 260 }
                NumberAnimation { target: matrix; property: "glare"
                                  to: 1.00; duration: 260 }
            }
            PauseAnimation { duration: 420 }
            // 4. the lights come up
            ScriptAction { script: matrix.stage = 3 }
            PauseAnimation { duration: 1500 }
            NumberAnimation { target: matrix; property: "bloom"; to: 1; duration: 480 }
            ScriptAction { script: win.send({ action: "open", target: matrix.target,
                                              tor: matrix.viaTor }) }
            PauseAnimation { duration: 400 }
            NumberAnimation { target: matrix; property: "bloom"; to: 0; duration: 420 }
            ScriptAction { script: { matrix.stage = 0; win.phase = "detail" } }
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
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (e) {
            // While you are typing, the box keeps ordinary text keys. But once a
            // system exists, Left/Right belong to the planets — otherwise they
            // silently move the text cursor and nothing appears to respond.
            if (query.activeFocus) {
                var steers = (e.key === Qt.Key_Escape || e.key === Qt.Key_Tab
                              || e.key === Qt.Key_Down || e.key === Qt.Key_Up)
                var arrows = (e.key === Qt.Key_Left || e.key === Qt.Key_Right)
                if (arrows && win.phase !== "idle") {
                    query.focus = false
                    keys.forceActiveFocus()
                } else if (!steers) {
                    return
                }
            }

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
    Shortcut { sequence: "Ctrl+L"; onActivated: query.forceActiveFocus() }

    onClosing: {
        var x = new XMLHttpRequest()
        x.open("PUT", "file://" + here("request.json"))
        x.send(JSON.stringify({ quit: true }))
    }
}
