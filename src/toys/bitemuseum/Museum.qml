import QtQuick
import QtQuick.Window

Window {
    id: root
    visible: true
    width: 1600
    height: 900
    color: "#040507"
    title: "BITE-OS Device Museum"
    visibility: shot.length > 0 ? Window.Windowed : Window.FullScreen

    // ── palette ───────────────────────────────────────────────────────────────
    readonly property color accent:  "#00ff88"
    readonly property color accent2: "#00dcff"
    readonly property color accent3: "#ff2ecc"
    readonly property color dimTxt:  "#6b7280"
    readonly property color txt:     "#e8ecf1"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // Everything is authored against 1600x900 and multiplied by this, so a
    // 1080p or 1440p screen gets proportionally larger type and spacing rather
    // than the same small block clinging to the top-left corner.
    readonly property real su: Math.max(0.8, Math.min(width / 1600, height / 900))
    function s(n) { return Math.round(n * su) }

    // ── state ─────────────────────────────────────────────────────────────────
    property var db: null
    property int chapter: 0
    readonly property int chapterCount: 8
    property bool redact: true
    property bool touring: false
    property string shot: ""
    property int sel: 0
    property string toast: ""
    property bool helpOpen: true

    // Every animation below targets an explicit id. `target: parent` inside an
    // animation silently binds to nothing — animations are not visual children —
    // which once left every plaque stuck at opacity 0 and the screen blank.

    function slurp(name, done) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) {
                try { done(JSON.parse(x.responseText)) } catch (e) { done(null) }
            }
        }
        x.open("GET", name)
        x.send()
    }

    Component.onCompleted: {
        slurp("opts.json", function (o) {
            if (o) {
                if (o.shot) root.shot = o.shot
                if (o.chapter !== undefined) root.chapter = o.chapter
                if (o.redact !== undefined) root.redact = o.redact
                if (o.selftest) selfTest.running = true
            }
            slurp("museum.json", function (d) {
                root.db = d
                if (root.shot.length) shotTimer.start()
            })
        })
    }

    // ── what ↑↓ and Enter act on, per chapter ─────────────────────────────────
    function listFor(c) {
        if (!db) return []
        if (c === 2) return db.oldest
        if (c === 3) return db.photos
        if (c === 4) return db.first_web
        if (c === 5) return db.biggest
        if (c === 6) return db.forgotten
        return []
    }
    function listCount() { return listFor(chapter).length }

    function openSelected() {
        var l = listFor(chapter)
        if (!l.length || sel < 0 || sel >= l.length) return
        var item = l[sel]
        if (item.url !== undefined) {
            if (redact) { flash("press B to reveal before opening"); return }
            Qt.openUrlExternally(item.url)
            flash("opening " + item.host)
        } else if (item.path !== undefined) {
            Qt.openUrlExternally("file://" + item.path)
            flash("opening " + item.name)
        }
    }
    function revealSelected() {
        var l = listFor(chapter)
        if (!l.length || sel >= l.length || l[sel].path === undefined) return
        var p = l[sel].path
        Qt.openUrlExternally("file://" + p.substring(0, p.lastIndexOf("/")))
        flash("opening the folder")
    }
    function flash(m) { root.toast = m; toastTimer.restart() }

    Timer { id: toastTimer; interval: 2400; onTriggered: root.toast = "" }
    Timer {
        id: selfTest
        interval: 320; repeat: true; running: false
        onTriggered: root.chapter < root.chapterCount ? root.chapter++ : Qt.exit(0)
    }
    Timer {
        id: shotTimer
        interval: 900
        onTriggered: stage.grabToImage(function (r) {
            r.saveToFile(root.shot); Qt.quit()
        }, Qt.size(root.width, root.height))
    }
    Timer {
        id: tourTimer
        interval: 7000; repeat: true; running: root.touring
        onTriggered: root.chapter < root.chapterCount ? root.chapter++
                                                      : root.touring = false
    }

    function fmtDate(unix) { return Qt.formatDate(new Date(unix * 1000), "d MMM yyyy") }
    function years(n) { return n === 1 ? "1 year" : n + " years" }

    property int fxKind: 0
    onChapterChanged: {
        sel = 0
        // A different transition every time — the same wipe twice in a row is
        // what made the old one feel flat.
        fxKind = Math.floor(Math.random() * 5)
        fx.sourceComponent = [cFxHandshake, cFxSlice, cFxMosaic,
                              cFxBeam, cFxSlam][fxKind]
    }
    readonly property var chapterNames: [
        "WELCOME", "GENESIS", "FIRST_LIGHT", "FIRST_PHOTOS", "THE_WEB",
        "HALL_OF_GIANTS", "THE_FORGOTTEN", "CURIOSITIES", "THE_COLLECTION"
    ]

    // ── background: a terminal, not a black rectangle ─────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#070a10" }
            GradientStop { position: 0.5; color: "#040507" }
            GradientStop { position: 1.0; color: "#080611" }
        }
    }

    // Scanlines and a phosphor grid, painted ONCE. Repainting a Canvas every
    // frame is the quickest way to lose 60fps, so everything that actually
    // moves below is a plain animated Item instead.
    Canvas {
        anchors.fill: parent
        onPaint: {
            var c = getContext("2d")
            c.clearRect(0, 0, width, height)
            c.strokeStyle = "rgba(255,255,255,0.028)"
            c.lineWidth = 1
            for (var y = 0; y < height; y += 3) {
                c.beginPath(); c.moveTo(0, y + 0.5); c.lineTo(width, y + 0.5); c.stroke()
            }
            c.strokeStyle = "rgba(0,255,136,0.030)"
            for (var x = 0; x < width; x += 46) {
                c.beginPath(); c.moveTo(x + 0.5, 0); c.lineTo(x + 0.5, height); c.stroke()
            }
            for (var gy = 0; gy < height; gy += 46) {
                c.beginPath(); c.moveTo(0, gy + 0.5); c.lineTo(width, gy + 0.5); c.stroke()
            }
        }
    }

    // A CRT beam drifting down the screen.
    Rectangle {
        id: beam
        width: parent.width
        height: 170
        y: -height
        gradient: Gradient {
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.45; color: Qt.rgba(0, 1, 0.55, 0.04) }
            GradientStop { position: 0.5;  color: Qt.rgba(0, 1, 0.55, 0.07) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 1, 0.55, 0.04) }
            GradientStop { position: 1.0;  color: "transparent" }
        }
        NumberAnimation on y {
            running: true; loops: Animation.Infinite
            from: -180; to: root.height + 180; duration: 7200
        }
    }

    // Edge falloff so the corners sit back.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.5) }
            GradientStop { position: 0.16; color: "transparent" }
            GradientStop { position: 0.84; color: "transparent" }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }

    // ── reusable bits ─────────────────────────────────────────────────────────

    // Types a string out one character at a time, with a block cursor.
    component Typed: Text {
        id: tw
        property string full: ""
        property int step: 26
        property int startDelay: 0
        property int shown: 0
        text: full.substring(0, shown)
        Component.onCompleted: twStart.start()
        Timer { id: twStart; interval: tw.startDelay; onTriggered: twTick.start() }
        Timer {
            id: twTick
            interval: tw.step; repeat: true
            onTriggered: { if (tw.shown < tw.full.length) tw.shown++; else twTick.stop() }
        }
        Rectangle {
            visible: tw.shown < tw.full.length && tw.full.length > 0
            width: tw.font.pixelSize * 0.5
            height: tw.font.pixelSize * 0.95
            color: root.accent
            x: tw.contentWidth + 3
            y: tw.font.pixelSize * 0.15
            opacity: 0.85
        }
    }

    component Plaque: Rectangle {
        id: pq
        property string title: ""
        property string sub: ""
        property string meta: ""
        property bool selected: false
        property int delay: 0
        height: root.s(56)
        radius: 3
        color: selected ? "#12212c" : "#0a0d12"
        border.color: selected ? root.accent : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        opacity: 0
        x: -26
        Behavior on color { ColorAnimation { duration: 130 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Component.onCompleted: pqIn.start()
        SequentialAnimation {
            id: pqIn
            PauseAnimation { duration: pq.delay }
            ParallelAnimation {
                NumberAnimation { target: pq; property: "opacity"; to: 1
                                  duration: 360; easing.type: Easing.OutCubic }
                NumberAnimation { target: pq; property: "x"; to: 0
                                  duration: 480; easing.type: Easing.OutBack }
            }
        }
        Rectangle {
            width: pq.selected ? 5 : 3
            height: parent.height - 18
            y: root.s(9)
            color: pq.selected ? root.accent : Qt.rgba(0, 1, 0.53, 0.5)
            Behavior on width { NumberAnimation { duration: 130 } }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.s(18)
            spacing: 2
            Text {
                text: pq.title
                color: pq.selected ? root.accent : root.txt
                font.family: root.mono; font.pixelSize: root.s(16); font.bold: true
                elide: Text.ElideMiddle; width: root.width * 0.62
                horizontalAlignment: Text.AlignLeft
            }
            Text {
                // Paths can contain Hebrew. Without an explicit left alignment a
                // right-to-left run drags the whole line across the row.
                text: pq.sub
                color: root.dimTxt; font.family: root.mono; font.pixelSize: root.s(11)
                elide: Text.ElideMiddle; width: root.width * 0.62
                horizontalAlignment: Text.AlignLeft
                LayoutMirroring.enabled: false
            }
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: root.s(18)
            anchors.verticalCenter: parent.verticalCenter
            text: pq.meta; color: root.accent2
            font.family: root.mono; font.pixelSize: root.s(13)
        }
    }

    component ChapterTitle: Item {
        id: ct
        property string roman: ""
        property string label: ""
        property string blurb: ""
        height: root.s(112)
        Text {
            id: rn
            text: ct.roman; color: root.accent3; font.family: root.mono
            font.pixelSize: root.s(12); font.letterSpacing: 6; opacity: 0
            Component.onCompleted: rnA.start()
            NumberAnimation { id: rnA; target: rn; property: "opacity"
                              to: 0.9; duration: 420 }
        }
        Typed {
            y: root.s(20); full: ct.label; step: 34; startDelay: 200
            color: root.txt; font.family: root.mono
            font.pixelSize: root.s(42); font.bold: true; font.letterSpacing: 3
        }
        Text {
            id: bl
            y: root.s(84); text: ct.blurb; color: root.dimTxt
            font.family: root.mono; font.pixelSize: root.s(13); opacity: 0
            Component.onCompleted: blA.start()
            SequentialAnimation {
                id: blA
                PauseAnimation { duration: 460 }
                NumberAnimation { target: bl; property: "opacity"; to: 1
                                  duration: 600; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── chapters ──────────────────────────────────────────────────────────────
    Component {
        id: cWelcome
        Item {
            anchors.fill: parent
            Column {
                x: root.s(80); y: root.s(70); spacing: 3
                Repeater {
                    model: db ? [
                        "> mounting " + db.root,
                        "> indexing " + db.totals.files.toLocaleString() + " objects",
                        "> earliest record " + db.totals.span_years + " years back",
                        "> curator ready"
                    ] : []
                    Typed {
                        full: modelData; step: 11; startDelay: 140 + index * 300
                        color: root.accent; font.family: root.mono
                        font.pixelSize: root.s(13); opacity: 0.5
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: root.s(16)
                Text {
                    id: w1
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "W E L C O M E   T O"
                    color: root.dimTxt; font.family: root.mono
                    font.pixelSize: root.s(17); font.letterSpacing: 10; opacity: 0
                    Component.onCompleted: a1.start()
                    SequentialAnimation {
                        id: a1
                        PauseAnimation { duration: 1450 }
                        NumberAnimation { target: w1; property: "opacity"
                                          to: 1; duration: 700 }
                    }
                }
                Rectangle {
                    id: box
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Sized from the text it contains, never a magic number. The
                    // old cap was a hardcoded 1180px while the font scaled with
                    // the screen, so on anything above 1600 wide the title grew
                    // and the box did not — the words punched straight out of it.
                    property real full: measure.contentWidth + root.s(64)
                    property bool ready: false
                    width: ready ? full : 0
                    height: measure.contentHeight + root.s(52)
                    color: "transparent"
                    border.color: root.accent; border.width: 2
                    Behavior on width {
                        NumberAnimation { duration: 850; easing.type: Easing.OutExpo }
                    }
                    Component.onCompleted: a2.start()
                    Timer { id: a2; interval: 1650; onTriggered: box.ready = true }

                    // Invisible, full-length copy used only to measure. The
                    // visible one is still typing, so its width is useless.
                    Text {
                        id: measure
                        visible: false
                        text: titleText.full
                        font.family: root.mono; font.pixelSize: titleText.font.pixelSize
                        font.bold: true; font.letterSpacing: titleText.font.letterSpacing
                    }
                    Typed {
                        id: titleText
                        anchors.centerIn: parent
                        full: db ? (db.user + "'s").toUpperCase() + "  DEVICE  MUSEUM" : ""
                        step: 40; startDelay: 2250
                        color: root.txt; font.family: root.mono; font.bold: true
                        font.letterSpacing: root.s(4)
                        // Shrink rather than overflow if the name is very long or
                        // the window is narrow.
                        font.pixelSize: Math.min(root.s(38),
                            (root.width * 0.84) / Math.max(12, full.length) / 0.66)
                    }
                }
                Text {
                    id: est
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: db && db.install_date
                          ? "established  " + db.install_date + "   ·   " +
                            db.install_age_days + " days of history" : ""
                    color: root.accent2; font.family: root.mono
                    font.pixelSize: root.s(15); opacity: 0
                    Component.onCompleted: a4.start()
                    SequentialAnimation {
                        id: a4
                        PauseAnimation { duration: 3300 }
                        NumberAnimation { target: est; property: "opacity"
                                          to: 1; duration: 700 }
                    }
                }
                Text {
                    id: hint
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "press  →  to walk through   ·   T for the guided tour"
                    color: root.dimTxt; font.family: root.mono
                    font.pixelSize: root.s(12); opacity: 0
                    Component.onCompleted: a5.start()
                    SequentialAnimation {
                        id: a5
                        PauseAnimation { duration: 3800 }
                        NumberAnimation { target: hint; property: "opacity"
                                          to: 0.85; duration: 800 }
                    }
                }
            }
        }
    }

    Component {
        id: cGenesis
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(80)
                roman: "C H A P T E R   I"; label: "GENESIS"
                blurb: "the day this machine came into being"
            }
            Column {
                x: root.s(80); y: root.s(250); spacing: root.s(20)
                Typed {
                    full: db && db.install_date ? db.install_date : "unknown"
                    step: 85; startDelay: 480
                    color: root.accent; font.family: root.mono
                    font.pixelSize: root.s(88); font.bold: true
                }
                Text {
                    text: db && db.install_time
                          ? "at " + db.install_time + "  ·  " + db.host : ""
                    color: root.dimTxt; font.family: root.mono; font.pixelSize: root.s(17)
                }
                Text {
                    text: db && db.install_age_days
                          ? "That was " + db.install_age_days +
                            " days ago. Everything here has arrived since." : ""
                    color: root.txt; font.family: root.mono; font.pixelSize: root.s(19)
                }
            }
        }
    }

    Component {
        id: cFirstLight
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(56)
                roman: "C H A P T E R   I I"; label: "FIRST LIGHT"
                blurb: "the oldest things you still carry"
            }
            ListView {
                id: lv
                x: root.s(80); y: root.s(186)
                width: root.width - root.s(160)
                height: root.height - root.s(186) - root.s(84)
                spacing: root.s(7)
                clip: true
                model: db ? db.oldest.length : 0
                currentIndex: root.sel
                highlightMoveDuration: 180
                preferredHighlightBegin: height * 0.25
                preferredHighlightEnd: height * 0.75
                highlightRangeMode: ListView.ApplyRange
                delegate: Plaque {
                    width: lv.width
                    delay: Math.min(index, 12) * 40
                    selected: index === root.sel
                    title: db.oldest[index].name
                    sub: db.oldest[index].dir
                    meta: root.fmtDate(db.oldest[index].mtime)
                }
            }
            Text {
                x: root.s(80)
                y: root.height - root.s(74)
                text: db ? (root.sel + 1) + " / " + db.oldest.length + "   ↑↓ to walk the room" : ""
                color: root.dimTxt; font.family: root.mono
                font.pixelSize: root.s(11); opacity: 0.65
            }
        }
    }

    Component {
        id: cPhotos
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(50)
                roman: "C H A P T E R   I I I"; label: "FIRST PHOTOS"
                blurb: "the earliest images in the collection"
            }
            GridView {
                id: gv
                x: root.s(80); y: root.s(180)
                width: root.width - root.s(160)
                height: root.height - root.s(180) - root.s(84)
                cellWidth: width / Math.max(4, Math.floor(width / root.s(300)))
                cellHeight: cellWidth * 0.72 + root.s(52)
                clip: true
                model: db ? db.photos.length : 0
                currentIndex: root.sel
                highlightMoveDuration: 180
                preferredHighlightBegin: height * 0.2
                preferredHighlightEnd: height * 0.8
                highlightRangeMode: GridView.ApplyRange
                delegate: Item {
                    width: gv.cellWidth; height: gv.cellHeight
                    Rectangle {
                        id: card
                        property bool isSel: index === root.sel
                        anchors.fill: parent
                        anchors.margins: root.s(9)
                        color: isSel ? "#12212c" : "#0a0d12"
                        border.color: isSel ? root.accent : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        opacity: 0
                        Behavior on color { ColorAnimation { duration: 130 } }
                        Behavior on border.color { ColorAnimation { duration: 130 } }
                        Component.onCompleted: cIn.start()
                        SequentialAnimation {
                            id: cIn
                            PauseAnimation { duration: Math.min(index, 12) * 55 }
                            NumberAnimation { target: card; property: "opacity"
                                              to: 1; duration: 480 }
                        }
                        Image {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(8)
                            height: parent.height - root.s(46)
                            source: "file://" + db.photos[index].path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; clip: true
                        }
                        Column {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.s(7)
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(9)
                            Text {
                                text: db.photos[index].name
                                color: card.isSel ? root.accent : root.txt
                                font.family: root.mono; font.pixelSize: root.s(11)
                                width: card.width - root.s(18); elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignLeft
                            }
                            Text {
                                text: root.fmtDate(db.photos[index].mtime)
                                color: root.accent2; font.family: root.mono
                                font.pixelSize: root.s(10)
                            }
                        }
                    }
                }
            }
            Text {
                x: root.s(80); y: root.height - root.s(74)
                text: db ? (root.sel + 1) + " / " + db.photos.length + "   ↑↓ to walk the room" : ""
                color: root.dimTxt; font.family: root.mono
                font.pixelSize: root.s(11); opacity: 0.65
            }
        }
    }

    Component {
        id: cWeb
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(50)
                roman: "C H A P T E R   I V"; label: "THE WEB YOU WALKED"
                blurb: root.redact ? "hidden — press B to reveal"
                                   : "the first places you went, and the ones you kept returning to"
            }
            Row {
                x: root.s(80); y: root.s(190); spacing: root.s(70)
                Column {
                    spacing: 6
                    Text {
                        text: "FIRST VISITS"; color: root.accent3
                        font.family: root.mono; font.pixelSize: root.s(11); font.letterSpacing: 4
                        bottomPadding: 6
                    }
                    Repeater {
                        model: db ? db.first_web.length : 0
                        Rectangle {
                            width: root.s(460); height: root.s(29); radius: 2
                            color: index === root.sel ? "#12212c" : "transparent"
                            border.color: index === root.sel ? root.accent : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 130 } }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: root.s(8)
                                spacing: 14
                                Text {
                                    text: root.fmtDate(db.first_web[index].when)
                                    color: root.dimTxt; font.family: root.mono
                                    font.pixelSize: root.s(12); width: root.s(110)
                                }
                                Text {
                                    text: root.redact ? "••••••••••••"
                                                      : db.first_web[index].host
                                    color: index === root.sel ? root.accent : root.txt
                                    font.family: root.mono; font.pixelSize: root.s(14)
                                }
                            }
                        }
                    }
                }
                Column {
                    spacing: 6
                    Text {
                        text: "MOST VISITED"; color: root.accent3
                        font.family: root.mono; font.pixelSize: root.s(11); font.letterSpacing: 4
                        bottomPadding: 6
                    }
                    Repeater {
                        model: db ? db.top_web.length : 0
                        Item {
                            width: root.s(440); height: root.s(29)
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 14
                                Text {
                                    text: db.top_web[index].visits + "×"
                                    color: root.accent; font.family: root.mono
                                    font.pixelSize: root.s(12); width: root.s(58)
                                }
                                Text {
                                    text: root.redact ? "••••••••••••" : db.top_web[index].host
                                    color: root.txt; font.family: root.mono
                                    font.pixelSize: root.s(14)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cGiants
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(56)
                roman: "C H A P T E R   V"; label: "HALL OF GIANTS"
                blurb: "the heaviest objects in the collection"
            }
            ListView {
                id: lv
                x: root.s(80); y: root.s(186)
                width: root.width - root.s(160)
                height: root.height - root.s(186) - root.s(84)
                spacing: root.s(7)
                clip: true
                model: db ? db.biggest.length : 0
                currentIndex: root.sel
                highlightMoveDuration: 180
                preferredHighlightBegin: height * 0.25
                preferredHighlightEnd: height * 0.75
                highlightRangeMode: ListView.ApplyRange
                delegate: Plaque {
                    width: lv.width
                    delay: Math.min(index, 12) * 40
                    selected: index === root.sel
                    title: db.biggest[index].name
                    sub: db.biggest[index].dir
                    meta: db.biggest[index].human
                }
            }
            Text {
                x: root.s(80)
                y: root.height - root.s(74)
                text: db ? (root.sel + 1) + " / " + db.biggest.length + "   ↑↓ to walk the room" : ""
                color: root.dimTxt; font.family: root.mono
                font.pixelSize: root.s(11); opacity: 0.65
            }
        }
    }

    Component {
        id: cForgotten
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(56)
                roman: "C H A P T E R   V I"; label: "THE FORGOTTEN"
                blurb: "large, and untouched for years"
            }
            ListView {
                id: lv
                x: root.s(80); y: root.s(186)
                width: root.width - root.s(160)
                height: root.height - root.s(186) - root.s(84)
                spacing: root.s(7)
                clip: true
                model: db ? db.forgotten.length : 0
                currentIndex: root.sel
                highlightMoveDuration: 180
                preferredHighlightBegin: height * 0.25
                preferredHighlightEnd: height * 0.75
                highlightRangeMode: ListView.ApplyRange
                delegate: Plaque {
                    width: lv.width
                    delay: Math.min(index, 12) * 40
                    selected: index === root.sel
                    title: db.forgotten[index].name
                    sub: db.forgotten[index].dir + "  ·  " + db.forgotten[index].human
                    meta: "unopened " + root.years(Math.round((Date.now() / 1000 - db.forgotten[index].atime) / 31536000))
                }
            }
            Text {
                x: root.s(80)
                y: root.height - root.s(74)
                text: db ? (root.sel + 1) + " / " + db.forgotten.length + "   ↑↓ to walk the room" : ""
                color: root.dimTxt; font.family: root.mono
                font.pixelSize: root.s(11); opacity: 0.65
            }
            Text {
                visible: db && db.forgotten.length === 0
                x: root.s(80); y: root.s(200)
                text: "Nothing forgotten. You use everything you own."
                color: root.dimTxt; font.family: root.mono; font.pixelSize: root.s(17)
            }
        }
    }

    Component {
        id: cCuriosities
        Item {
            anchors.fill: parent
            ChapterTitle {
                x: root.s(80); y: root.s(56)
                roman: "C H A P T E R   V I I"; label: "CURIOSITIES"
                blurb: "the odd corners of the archive"
            }
            Column {
                x: root.s(80); y: root.s(210); spacing: root.s(32)
                Column {
                    spacing: 6
                    Text {
                        text: "THE LONGEST NAME"; color: root.accent3
                        font.family: root.mono; font.pixelSize: root.s(11); font.letterSpacing: 4
                    }
                    Text {
                        text: db && db.curiosities.longest_name
                              ? db.curiosities.longest_name.name : "—"
                        color: root.txt; font.family: root.mono; font.pixelSize: root.s(18)
                        width: root.width - 200; wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2; elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                    }
                }
                Column {
                    spacing: 6
                    Text {
                        text: "THE DEEPEST BURIED"; color: root.accent3
                        font.family: root.mono; font.pixelSize: root.s(11); font.letterSpacing: 4
                    }
                    Text {
                        text: db && db.curiosities.deepest ? db.curiosities.deepest.dir : "—"
                        color: root.txt; font.family: root.mono; font.pixelSize: root.s(15)
                        width: root.width - 200; wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3; elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }
    }

    Component {
        id: cClosing
        Item {
            anchors.fill: parent
            Column {
                anchors.centerIn: parent
                spacing: root.s(24)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "THE COLLECTION"; color: root.accent3
                    font.family: root.mono; font.pixelSize: root.s(12); font.letterSpacing: 8
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(62)
                    Repeater {
                        model: db ? [
                            { k: "objects",   v: db.totals.files.toLocaleString() },
                            { k: "occupying", v: db.totals.human },
                            { k: "images",    v: db.totals.images.toLocaleString() },
                            { k: "spanning",  v: db.totals.span_years + " yrs" }
                        ] : []
                        Column {
                            id: statCol
                            spacing: 6
                            opacity: 0
                            y: root.s(16)
                            Component.onCompleted: sIn.start()
                            SequentialAnimation {
                                id: sIn
                                PauseAnimation { duration: index * 200 }
                                ParallelAnimation {
                                    NumberAnimation { target: statCol; property: "opacity"
                                                      to: 1; duration: 600 }
                                    NumberAnimation { target: statCol; property: "y"
                                                      to: 0; duration: 700
                                                      easing.type: Easing.OutCubic }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.v; color: root.accent
                                font.family: root.mono; font.pixelSize: root.s(40); font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.k; color: root.dimTxt
                                font.family: root.mono; font.pixelSize: root.s(12)
                            }
                        }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: root.s(46)
                    spacing: root.s(7)
                    Text {
                        id: outro1
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "come back in a year — it will not say the same thing"
                        color: root.dimTxt; font.family: root.mono
                        font.pixelSize: root.s(13); opacity: 0
                        Component.onCompleted: o1.start()
                        SequentialAnimation {
                            id: o1
                            PauseAnimation { duration: 1400 }
                            NumberAnimation { target: outro1; property: "opacity"
                                              to: 0.75; duration: 1100 }
                        }
                    }
                    Text {
                        id: outro2
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "you are looking at who you were"
                        color: root.dimTxt; font.family: root.mono
                        font.pixelSize: root.s(13); opacity: 0
                        Component.onCompleted: o2.start()
                        SequentialAnimation {
                            id: o2
                            PauseAnimation { duration: 2300 }
                            NumberAnimation { target: outro2; property: "opacity"
                                              to: 0.55; duration: 1100 }
                        }
                    }
                    Text {
                        id: outro3
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "curated by BITE-OS"
                        color: root.dimTxt; font.family: root.mono
                        font.pixelSize: root.s(11); opacity: 0
                        topPadding: root.s(22)
                        Component.onCompleted: o3.start()
                        SequentialAnimation {
                            id: o3
                            PauseAnimation { duration: 3300 }
                            NumberAnimation { target: outro3; property: "opacity"
                                              to: 0.4; duration: 900 }
                        }
                    }
                }
            }
        }
    }

    // ── chapter transitions ───────────────────────────────────────────────────
    // Five of them, chosen at random per change. Each one self-destructs when
    // it finishes so nothing accumulates. All are plain animated Items — no
    // per-frame Canvas — so they stay cheap at 60fps.

    // 1. the machine talking its way into the next room
    Component {
        id: cFxHandshake
        Item {
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#04070a"; opacity: 0.93 }
            Column {
                x: root.s(80); y: root.height / 2 - root.s(80)
                spacing: root.s(6)
                Repeater {
                    model: [
                        "> closing  " + root.chapterNames[Math.max(0, root.chapter - 1)],
                        "> probing  " + root.chapterNames[root.chapter],
                        "> handshake ................ ok",
                        "> decrypting " + root.listCount() + " records",
                        "> access granted"
                    ]
                    Typed {
                        full: modelData; step: 5; startDelay: index * 90
                        color: index === 4 ? root.accent : root.accent2
                        font.family: root.mono; font.pixelSize: root.s(15)
                    }
                }
            }
            Rectangle {
                id: hbar
                x: root.s(80); y: root.height / 2 + root.s(70)
                width: 0; height: root.s(3); color: root.accent
                NumberAnimation on width {
                    to: root.width - root.s(160); duration: 620
                    easing.type: Easing.InOutQuad
                }
            }
            NumberAnimation on opacity {
                to: 0; duration: 260; easing.type: Easing.InQuad
                running: true; from: 1
                // hold, then dissolve
            }
            Timer { interval: 780; running: true; onTriggered: fx.sourceComponent = null }
        }
    }

    // 2. interlaced slices sweeping in from alternating sides
    Component {
        id: cFxSlice
        Item {
            anchors.fill: parent
            Column {
                anchors.fill: parent
                Repeater {
                    model: 16
                    Rectangle {
                        id: sl
                        width: root.width; height: root.height / 16
                        color: index % 2 ? "#06090d" : "#0a0f14"
                        x: index % 2 ? root.width : -root.width
                        SequentialAnimation {
                            running: true
                            NumberAnimation { target: sl; property: "x"; to: 0
                                              duration: 220 + index * 12
                                              easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 90 }
                            NumberAnimation { target: sl; property: "x"
                                              to: index % 2 ? -root.width : root.width
                                              duration: 260 + index * 10
                                              easing.type: Easing.InQuad }
                        }
                    }
                }
            }
            Timer { interval: 820; running: true; onTriggered: fx.sourceComponent = null }
        }
    }

    // 3. block dissolve
    Component {
        id: cFxMosaic
        Item {
            anchors.fill: parent
            Grid {
                anchors.fill: parent
                columns: 24; rows: 14
                Repeater {
                    model: 24 * 14
                    Rectangle {
                        id: blk
                        width: root.width / 24; height: root.height / 14
                        color: "#070b10"
                        opacity: 0
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: Math.random() * 220 }
                            NumberAnimation { target: blk; property: "opacity"
                                              to: 1; duration: 90 }
                            PauseAnimation { duration: 120 + Math.random() * 180 }
                            NumberAnimation { target: blk; property: "opacity"
                                              to: 0; duration: 200 }
                        }
                    }
                }
            }
            Timer { interval: 820; running: true; onTriggered: fx.sourceComponent = null }
        }
    }

    // 4. a scanner bar crossing the screen
    Component {
        id: cFxBeam
        Item {
            anchors.fill: parent
            Rectangle {
                id: bm
                width: root.s(140); height: root.height
                x: -width
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 1, 0.53, 0.30) }
                    GradientStop { position: 0.52; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                NumberAnimation on x {
                    to: root.width; duration: 560; easing.type: Easing.InOutQuad
                    running: true
                }
            }
            Timer { interval: 620; running: true; onTriggered: fx.sourceComponent = null }
        }
    }

    // 5. colour channels knocked apart, then slammed back
    Component {
        id: cFxSlam
        Item {
            anchors.fill: parent
            Repeater {
                model: 3
                Rectangle {
                    id: ch
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width; height: root.s(150)
                    color: index === 0 ? root.accent3 : index === 1 ? root.accent2 : root.accent
                    opacity: 0.30
                    x: (index - 1) * root.s(90)
                    ParallelAnimation {
                        running: true
                        NumberAnimation { target: ch; property: "x"; to: 0
                                          duration: 320; easing.type: Easing.OutExpo }
                        SequentialAnimation {
                            NumberAnimation { target: ch; property: "opacity"
                                              to: 0.30; duration: 120 }
                            NumberAnimation { target: ch; property: "opacity"
                                              to: 0; duration: 320 }
                        }
                        NumberAnimation { target: ch; property: "height"
                                          to: root.s(4); duration: 420
                                          easing.type: Easing.OutExpo }
                    }
                }
            }
            Timer { interval: 520; running: true; onTriggered: fx.sourceComponent = null }
        }
    }

    // ── stage ─────────────────────────────────────────────────────────────────
    Item {
        id: stage
        anchors.fill: parent

        Loader {
            id: page
            anchors.fill: parent
            sourceComponent: [cWelcome, cGenesis, cFirstLight, cPhotos, cWeb,
                              cGiants, cForgotten, cCuriosities, cClosing][root.chapter]
            opacity: 0
            Component.onCompleted: fadeIn.start()
            ParallelAnimation {
                id: fadeIn
                NumberAnimation { target: page; property: "opacity"
                                  to: 1; duration: 360 }
                NumberAnimation { target: page; property: "x"; from: 26; to: 0
                                  duration: 420; easing.type: Easing.OutCubic }
            }
            onSourceComponentChanged: { page.opacity = 0; fadeIn.restart() }
        }
    }

    // ── transition overlay ────────────────────────────────────────────────────
    Loader {
        id: fx
        anchors.fill: parent
        sourceComponent: null
    }

    // ── the key list, collapsible ─────────────────────────────────────────────
    Rectangle {
        id: helpPanel
        visible: opacity > 0.01
        opacity: root.helpOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.s(26)
        anchors.bottomMargin: root.s(56)
        width: helpCol.width + root.s(34)
        height: helpCol.height + root.s(28)
        color: "#080c11"
        border.color: Qt.rgba(0, 1, 0.53, 0.35)
        border.width: 1
        radius: 3
        Column {
            id: helpCol
            anchors.centerIn: parent
            spacing: root.s(4)
            Text {
                text: "KEYS"; color: root.accent3; font.family: root.mono
                font.pixelSize: root.s(11); font.letterSpacing: 4
                bottomPadding: root.s(5)
            }
            Repeater {
                model: [
                    ["\u2192 \u2190", "next / previous chapter"],
                    ["\u2191 \u2193", "select an exhibit"],
                    ["\u23ce", "open the selected file"],
                    ["F", "open its folder"],
                    ["T", "guided tour, hands-free"],
                    ["B", "reveal or hide urls"],
                    ["?", "show / hide this list"],
                    ["Q", "quit"]
                ]
                Row {
                    spacing: root.s(12)
                    Text {
                        text: modelData[0]; color: root.accent
                        font.family: root.mono; font.pixelSize: root.s(12)
                        width: root.s(34)
                    }
                    Text {
                        text: modelData[1]; color: root.dimTxt
                        font.family: root.mono; font.pixelSize: root.s(12)
                    }
                }
            }
        }
    }

    // ── chrome ────────────────────────────────────────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.s(32)
        spacing: 10
        Repeater {
            model: root.chapterCount + 1
            Rectangle {
                width: index === root.chapter ? 26 : 7
                height: 3; radius: 2
                color: index === root.chapter ? root.accent : "#242a33"
                Behavior on width { NumberAnimation { duration: 240
                                    easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 240 } }
            }
        }
    }

    Text {
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.s(26)
        text: root.touring ? "● GUIDED TOUR — advancing on its own" : ""
        color: root.accent3; font.family: root.mono; font.pixelSize: root.s(12)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(56)
        text: root.toast
        color: root.accent; font.family: root.mono; font.pixelSize: root.s(13)
        opacity: root.toast.length ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: root.s(26)
        text: root.listCount() > 0
              ? "↑↓ select · ⏎ open · F folder · → next · ← back · T tour · B " +
                (root.redact ? "reveal" : "hide") + " · Q quit"
              : "→ next · ← back · T tour · B " +
                (root.redact ? "reveal" : "hide") + " urls · Q quit"
        color: root.dimTxt; font.family: root.mono; font.pixelSize: root.s(11)
        opacity: 0.6
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (e) {
            var n = root.listCount()
            if (e.key === Qt.Key_Right || e.key === Qt.Key_Space) {
                if (root.chapter < root.chapterCount) root.chapter++
            } else if (e.key === Qt.Key_Left) {
                if (root.chapter > 0) root.chapter--
            } else if (e.key === Qt.Key_Down) {
                if (n) root.sel = (root.sel + 1) % n
            } else if (e.key === Qt.Key_Up) {
                if (n) root.sel = (root.sel - 1 + n) % n
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.openSelected()
            } else if (e.key === Qt.Key_F) {
                root.revealSelected()
            } else if (e.key === Qt.Key_Question || e.key === Qt.Key_Slash) {
                root.helpOpen = !root.helpOpen
            } else if (e.key === Qt.Key_T) {
                root.touring = !root.touring
            } else if (e.key === Qt.Key_B) {
                root.redact = !root.redact
            } else if (e.key === Qt.Key_Q || e.key === Qt.Key_Escape) {
                Qt.quit()
            }
        }
    }
}
