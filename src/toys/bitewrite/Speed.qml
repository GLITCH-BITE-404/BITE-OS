// SPEED mode: the text to type is the ghost, the clock starts on your first
// key, and your speed is live at the bottom the whole time — a rolling 5 second
// figure that glides rather than jumps, accuracy, the clock, and a sparkline of
// how it went. Timed runs end on a results card and keep your best per
// time/text combination; infinite never ends.

import QtQuick

Item {
    id: sp
    property var w
    property var page
    readonly property bool active: w.mode === "speed"
    anchors.fill: parent
    visible: active

    property var words: []
    property var sentences: []
    property var bests: ({})
    readonly property int duration: w.speedTime === "infinite" ? 0
                                  : (w.speedTime === "custom" ? w.speedCustom : Number(w.speedTime) || 60)
    readonly property string bestKey: (duration ? duration + "s" : "infinite") + " · " + w.speedText
    property bool started: false
    property bool finished: false
    property real t0: 0
    property real elapsed: 0
    property int correct: 0            // characters right, from align.js, set by the page
    property int keys: 0
    property int errors: 0
    property var hist: []
    property var samples: []
    property real live: 0
    property real avg: 0
    property real shown: 0
    property bool newBest: false
    property real oldBest: 0
    readonly property int acc: keys ? Math.max(0, Math.round((keys - errors) / keys * 100)) : 100
    readonly property real raw: elapsed > 0.5 ? keys / 5 / (elapsed / 60) : 0
    Behavior on shown { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    function load() {
        w.readFile("speed.json", function(raw) {
            try { var o = JSON.parse(raw); sp.words = o.words || []; sp.sentences = o.sentences || []; } catch (e) {}
        });
        if (w.bestsPath) w.readFile(w.bestsPath, function(raw) {
            try { sp.bests = JSON.parse(raw) || {}; } catch (e) { sp.bests = {}; }
        });
    }

    function reset() {
        sp.started = false; sp.finished = false; sp.elapsed = 0; sp.correct = 0;
        sp.keys = 0; sp.errors = 0; sp.hist = []; sp.samples = [];
        sp.live = 0; sp.avg = 0; sp.shown = 0; sp.newBest = false;
    }

    // ── what to type ────────────────────────────────────────────────────────
    function pick(a) { return a[Math.floor(Math.random() * a.length)]; }
    function hardWord() {
        var wd = pick(sp.words);
        if (Math.random() < 0.12) return String(Math.floor(Math.random() * 999));
        if (Math.random() < 0.3) wd = wd[0].toUpperCase() + wd.slice(1);
        if (Math.random() < 0.25) wd += pick([",", ".", ";", "!", "?", ":"]);
        if (Math.random() < 0.06) wd = "(" + wd + ")";
        if (Math.random() < 0.05) wd = wd + "-" + pick(sp.words);
        return wd;
    }
    function chunk() {
        var out = [], n;
        if (!sp.words.length) sp.words = ["type", "fast", "and", "keep", "going"];
        if (w.speedText === "sentences" && sp.sentences.length) {
            for (n = 0; n < 5; n++) out.push(pick(sp.sentences));
            return out.join(" ");
        }
        if (w.speedText === "hard") {
            for (n = 0; n < 45; n++) out.push(hardWord());
            return out.join(" ");
        }
        if (w.speedText === "page") {
            var p = (w.writeText || "").replace(/\s+/g, " ").trim();
            if (p.length > 20) return p;
            w.toast("your WRITE page is empty — using random words");
        }
        for (n = 0; n < 50; n++) out.push(pick(sp.words));
        return out.join(" ");
    }
    function wrap(text) {
        var C = Math.max(24, Math.min(56, w.maxCols, w.fitColsAt(w.userPx)));
        var rows = [], line = "";
        text.split(" ").forEach(function(wd) {
            if (!wd) return;
            if (line.length && line.length + 1 + wd.length > C) { rows.push(line); line = wd; }
            else line = line.length ? line + " " + wd : wd;
        });
        if (line.length) rows.push(line);
        return rows;
    }
    function generate() { reset(); return wrap(chunk()).join("\n"); }
    function more() { return wrap(chunk()); }

    // ── the clock ───────────────────────────────────────────────────────────
    function onKey(kind) {
        if (sp.finished) return;
        if (!sp.started) { sp.started = true; sp.t0 = Date.now(); }
        sp.keys++;
        if (kind === "error") sp.errors++;
    }

    Timer {
        interval: 100
        repeat: true
        running: sp.active && sp.started && !sp.finished
        onTriggered: {
            var e = (Date.now() - sp.t0) / 1000;
            sp.elapsed = e;
            var h = sp.hist;
            h.push({ t: e, c: sp.correct });
            while (h.length > 2 && e - h[0].t > 5) h.shift();
            sp.hist = h;
            var o = h[0], dt = e - o.t;
            sp.live = dt > 0.6 ? Math.max(0, (sp.correct - o.c) / 5 / (dt / 60)) : 0;
            sp.avg = e > 0.5 ? sp.correct / 5 / (e / 60) : 0;
            sp.shown = e < 5 ? sp.avg : sp.live;
            if (Math.floor(e) > sp.samples.length) {
                var s = sp.samples.slice(); s.push(Math.round(sp.shown)); sp.samples = s;
            }
            if (sp.duration && e >= sp.duration) sp.finish();
        }
    }

    function finish() {
        if (sp.finished) return;
        sp.elapsed = sp.duration || sp.elapsed;
        sp.avg = sp.elapsed > 0 ? sp.correct / 5 / (sp.elapsed / 60) : 0;
        sp.shown = sp.avg;
        sp.finished = true;
        sp.oldBest = sp.bests[sp.bestKey] || 0;
        sp.newBest = sp.keys > 0 && Math.round(sp.avg) > sp.oldBest;
        if (sp.newBest) {
            var b = Object.assign({}, sp.bests);
            b[sp.bestKey] = Math.round(sp.avg);
            sp.bests = b;
            if (w.bestsPath) w.writeFile(w.bestsPath, JSON.stringify(b));
            w.celebrate();
        }
        w.sfx.play("done");
        cardPop.restart();
    }

    function clock(s) {
        s = Math.max(0, Math.ceil(s));
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + s % 60;
    }

    component Spark: Canvas {
        property var values: []
        property string ink: "white"
        onValuesChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!values || values.length < 2) return;
            var mx = Math.max(40, Math.max.apply(null, values)), n = values.length;
            ctx.strokeStyle = ink;
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.beginPath();
            for (var i = 0; i < n; i++) {
                var x = i / (n - 1) * (width - 4) + 2, y = height - 2 - values[i] / mx * (height - 4);
                if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
            }
            ctx.stroke();
        }
    }

    // ── top: pick the time and the text ─────────────────────────────────────
    property real leftLimit: 0         // right edge of the mode tabs — don't overlap them
    Row {
        id: chips
        spacing: 14
        x: Math.max(sp.leftLimit, sp.page.x + (sp.page.width - width) / 2)
        y: sp.page.y - height - 12
        Repeater {
            model: ["15", "30", "60", "120", "infinite", "custom"]
            delegate: Text {
                readonly property bool on: w.speedTime === modelData
                text: modelData === "infinite" ? "∞" : modelData === "custom" ? "custom " + w.speedCustom + "s" : modelData + "s"
                font.family: w.fontFamily
                font.pixelSize: 13
                color: on ? w.cAccent : w.cSub
                opacity: on ? 1 : 0.55
                MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: w.setSetting("speed_time", modelData) }
            }
        }
        Text { text: "·"; font.pixelSize: 13; color: w.cSub; opacity: 0.4 }
        Repeater {
            model: ["words", "sentences", "hard", "page"]
            delegate: Text {
                readonly property bool on: w.speedText === modelData
                text: modelData
                font.family: w.fontFamily
                font.pixelSize: 13
                color: on ? w.cAccent : w.cSub
                opacity: on ? 1 : 0.55
                MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: w.setSetting("speed_text", modelData) }
            }
        }
    }

    // ── the clock running down along the bottom of the page ─────────────────
    Rectangle {
        visible: sp.duration > 0 && sp.started
        x: sp.page.x + 24
        y: sp.page.y + sp.page.height - 7
        height: 3
        radius: 1.5
        width: (sp.page.width - 48) * Math.max(0, 1 - sp.elapsed / Math.max(1, sp.duration))
        color: w.cAccent
        opacity: 0.8
    }

    // ── bottom: live speed ──────────────────────────────────────────────────
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: sp.page.y + sp.page.height + 18
        visible: !sp.started
        text: "the clock starts on your first key   ·   tab time   ·   shift+tab text   ·   ctrl+r new text   ·   esc back"
        font.family: w.fontFamily
        font.pixelSize: 12
        color: w.cSub
        opacity: 0.5
    }

    Row {
        id: bar
        visible: sp.started
        anchors.horizontalCenter: parent.horizontalCenter
        y: sp.page.y + sp.page.height + 8
        spacing: 22
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: big
                text: Math.round(sp.shown)
                font.family: w.fontFamily
                font.pixelSize: 30
                font.bold: true
                color: w.mix(w.cSub, w.cAccent, Math.min(1, sp.shown / 110))
            }
            Text {
                anchors.baseline: big.baseline
                text: "wpm"
                font.family: w.fontFamily
                font.pixelSize: 12
                color: w.cSub
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sp.acc + "% acc"
            font.family: w.fontFamily
            font.pixelSize: 13
            color: sp.acc < 90 ? w.cBad : w.cSub
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sp.duration ? sp.clock(sp.duration - sp.elapsed) + " left" : sp.clock(sp.elapsed) + "   ·   avg " + Math.round(sp.avg)
            font.family: w.fontFamily
            font.pixelSize: 13
            color: w.cSub
        }
        Spark {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            height: 26
            values: sp.samples
            ink: w.cAccent.toString()
        }
    }

    // ── the results card ────────────────────────────────────────────────────
    Rectangle {
        id: card
        visible: opacity > 0
        opacity: sp.finished ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        width: Math.min(500, sp.page.width - 40)
        height: 360
        x: sp.page.x + (sp.page.width - width) / 2
        y: sp.page.y + (sp.page.height - height) / 2
        radius: w.radius * 1.6
        color: w.cPage
        border.width: 1
        border.color: Qt.alpha(w.cAccent, 0.5)

        SequentialAnimation {
            id: cardPop
            NumberAnimation { target: card; property: "scale"; from: 0.9; to: 1.04; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: card; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "TIME'S UP   ·   " + sp.bestKey
                font.family: w.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
                color: w.cSub
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    id: result
                    text: Math.round(sp.avg)
                    font.family: w.fontFamily
                    font.pixelSize: 84
                    font.bold: true
                    color: w.cAccent
                }
                Text {
                    anchors.baseline: result.baseline
                    text: "wpm"
                    font.family: w.fontFamily
                    font.pixelSize: 16
                    color: w.cSub
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sp.acc + "% accuracy   ·   raw " + Math.round(sp.raw) + "   ·   " + sp.keys + " keys"
                font.family: w.fontFamily
                font.pixelSize: 13
                color: w.cText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sp.newBest ? "★ new best" + (sp.oldBest ? " — was " + sp.oldBest : "") : "best " + sp.oldBest
                font.family: w.fontFamily
                font.pixelSize: 14
                font.bold: sp.newBest
                color: sp.newBest ? w.cAccent : w.cSub
            }
            Spark {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(400, card.width - 60)
                height: 70
                values: sp.samples
                ink: w.cAccent.toString()
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "enter again   ·   tab time   ·   shift+tab text   ·   esc back"
                font.family: w.fontFamily
                font.pixelSize: 11
                color: w.cSub
                opacity: 0.6
            }
        }
    }
}
