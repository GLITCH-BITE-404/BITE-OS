// Runs the code you typed. It really is your text: compiled with new Function
// and handed a canvas, so a typo that compiles runs as a typo.
//
// A snippet defines frame(t), t in seconds, and draws with ctx (a normal
// 2D canvas context). Also in scope: W H, ACCENT TEXT BASE, rand() pick(str)
// hsl(h, s, l, a), and PI sin cos tan abs floor ceil round sqrt min max atan2.

import QtQuick

Item {
    id: stage
    property var w
    property bool running: false
    property var frameFn: null
    property real t0: 0
    property string error: ""
    property int errorLine: -1
    property int lineOffset: 0
    signal failed(string message, int line)
    signal stopped()

    visible: opacity > 0
    opacity: running ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property var names: ["ctx", "W", "H", "ACCENT", "TEXT", "BASE", "rand", "pick", "hsl",
        "PI", "sin", "cos", "tan", "abs", "floor", "ceil", "round", "sqrt", "min", "max", "atan2"]

    function css(c) {
        return "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " +
               Math.round(c.b * 255) + ", " + c.a + ")";
    }
    function hsl(h, s, l, a) {
        var c = Qt.hsla((((h % 360) + 360) % 360) / 360, Math.max(0, Math.min(1, s / 100)),
                        Math.max(0, Math.min(1, l / 100)), a === undefined ? 1 : Math.max(0, Math.min(1, a)));
        return css(c);
    }

    // A runtime error's line counts from the top of the wrapper V4 builds
    // around a Function body, not from the snippet's first line — measured
    // once here. Parse errors are no help at all: V4 reports every one of
    // them on the same fixed line, so those get no line number.
    Component.onCompleted: {
        try { new Function("a", "throw new Error('probe')")(); } catch (e) { stage.lineOffset = (e.lineNumber || 1) - 1; }
    }

    function lineOf(e) {
        if (!e || e.name === "SyntaxError" || !e.lineNumber) return -1;
        var n = e.lineNumber - stage.lineOffset;
        return n > 0 ? n : -1;
    }

    // compile only — the page uses it to say "compiles" before you run it
    function check(code) {
        try {
            new Function(stage.names.join(","), code + "\nreturn typeof frame === 'function' ? frame : null");
            return { ok: true };
        } catch (e) {
            return { ok: false, message: String(e.message || e), line: lineOf(e) };
        }
    }

    function run(code) {
        stage.error = "";
        var ctx = canvas.getContext("2d");
        ctx.reset();
        ctx.fillStyle = "black";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        try {
            var make = new Function(stage.names.join(","), code + "\nreturn typeof frame === 'function' ? frame : null");
            var f = make(ctx, canvas.width, canvas.height, css(w.cAccent), css(w.cText), css(w.cBase),
                Math.random, function(s) { return s[Math.floor(Math.random() * s.length)]; }, stage.hsl,
                Math.PI, Math.sin, Math.cos, Math.tan, Math.abs, Math.floor, Math.ceil, Math.round,
                Math.sqrt, Math.min, Math.max, Math.atan2);
            if (typeof f !== "function") {
                stage.failed("there's no function frame(t) — that's what gets called every frame", -1);
                return false;
            }
            stage.frameFn = f;
        } catch (e) {
            stage.failed(String(e.message || e), lineOf(e));
            return false;
        }
        stage.t0 = Date.now();
        stage.running = true;
        stage.forceActiveFocus();
        return true;
    }

    function stop() {
        if (!stage.running) return;
        stage.running = false;
        stage.frameFn = null;
        stage.stopped();
    }

    Rectangle { anchors.fill: parent; color: "black" }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative
        onPaint: {
            if (!stage.frameFn) return;
            var ctx = getContext("2d");
            try {
                stage.frameFn((Date.now() - stage.t0) / 1000);
            } catch (e) {
                var msg = String(e.message || e), line = stage.lineOf(e);
                stage.frameFn = null;
                stage.running = false;
                stage.failed(msg, line);
            }
        }
    }

    FrameAnimation {
        running: stage.running
        onTriggered: canvas.requestPaint()
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 18
        text: "▶ your code, running   ·   any key to stop"
        font.family: w.fontFamily
        font.pixelSize: 12
        color: "white"
        opacity: 0.45
    }

    Keys.onPressed: function(e) { stage.stop(); e.accepted = true; }
    MouseArea { anchors.fill: parent; onClicked: stage.stop() }
}
