// Runs the code you typed. It really is your text: compiled with new Function
// and handed a canvas, so a typo that compiles runs as a typo.
//
// A program defines frame(t), t in seconds, and draws with ctx (a normal 2D
// canvas context). It can also be played: the keyboard and the mouse go to it
// while it runs, and only Esc or the stop button take you back.
//
// In scope: W H, ACCENT TEXT BASE, rand() pick(str) hsl(h, s, l, a),
//   keys     which keys are held — keys.up, keys.space, keys.a …
//   mouse    { x, y, down }
// PI sin cos tan abs floor ceil round sqrt min max atan2 pow exp log hypot sign.
// Optional: onKey(k) and onKeyUp(k) when a key goes down / up, onClick(x, y).
// Key names: up down left right space enter tab backspace shift ctrl, and
// letters and digits as themselves in lower case.

import QtQuick

Item {
    id: stage
    property var w
    property bool running: false
    property var prog: null
    property var keysHeld: ({})
    property var mouseState: ({ x: 0, y: 0, down: false })
    property real t0: 0
    property int lineOffset: 0
    signal failed(string message, int line)
    signal stopped()

    visible: opacity > 0
    opacity: running ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property var names: ["ctx", "W", "H", "ACCENT", "TEXT", "BASE", "rand", "pick", "hsl", "keys", "mouse",
        "PI", "sin", "cos", "tan", "abs", "floor", "ceil", "round", "sqrt", "min", "max", "atan2",
        "pow", "exp", "log", "hypot", "sign"]
    readonly property string tail: "\nreturn { frame: typeof frame === 'function' ? frame : null," +
        " onKey: typeof onKey === 'function' ? onKey : null," +
        " onKeyUp: typeof onKeyUp === 'function' ? onKeyUp : null," +
        " onClick: typeof onClick === 'function' ? onClick : null }"

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
    // around a Function body, not from the program's first line — measured
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

    // compile only — the page uses it to say "runs" before you run it
    function check(code) {
        try {
            new Function(stage.names.join(","), code + stage.tail);
            return { ok: true };
        } catch (e) {
            return { ok: false, message: String(e.message || e), line: lineOf(e) };
        }
    }

    function run(code) {
        var ctx = canvas.getContext("2d");
        ctx.reset();
        // canvas text defaults to "start", which a Hebrew locale turns into
        // right-aligned — programs are written expecting text to start at x
        ctx.textAlign = "left";
        ctx.fillStyle = "black";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        stage.keysHeld = {};
        stage.mouseState = { x: canvas.width / 2, y: canvas.height / 2, down: false };
        try {
            var make = new Function(stage.names.join(","), code + stage.tail);
            var p = make(ctx, canvas.width, canvas.height, css(w.cAccent), css(w.cText), css(w.cBase),
                Math.random, function(s) { return s[Math.floor(Math.random() * s.length)]; }, stage.hsl,
                stage.keysHeld, stage.mouseState,
                Math.PI, Math.sin, Math.cos, Math.tan, Math.abs, Math.floor, Math.ceil, Math.round,
                Math.sqrt, Math.min, Math.max, Math.atan2,
                Math.pow, Math.exp, Math.log, Math.hypot, Math.sign);
            if (!p.frame) {
                stage.failed("there's no function frame(t) — that's what gets called every frame", -1);
                return false;
            }
            stage.prog = p;
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
        stage.prog = null;
        stage.stopped();
    }

    // every call into the program goes through here, so an error in a key
    // handler stops it with a message just like an error in frame()
    function call(name, a, b) {
        if (!stage.prog || !stage.prog[name]) return;
        try {
            stage.prog[name](a, b);
        } catch (e) {
            stage.prog = null;
            stage.running = false;
            stage.failed(String(e.message || e), lineOf(e));
        }
    }

    function keyName(e) {
        switch (e.key) {
        case Qt.Key_Up: return "up";
        case Qt.Key_Down: return "down";
        case Qt.Key_Left: return "left";
        case Qt.Key_Right: return "right";
        case Qt.Key_Space: return "space";
        case Qt.Key_Return: case Qt.Key_Enter: return "enter";
        case Qt.Key_Tab: return "tab";
        case Qt.Key_Backspace: return "backspace";
        case Qt.Key_Shift: return "shift";
        case Qt.Key_Control: return "ctrl";
        }
        return e.text.length === 1 && e.text > " " ? e.text.toLowerCase() : "";
    }

    // the same moves the real keyboard and mouse make (tests use these too)
    function press(k) { if (!k) return; stage.keysHeld[k] = true; call("onKey", k); }
    function release(k) { if (!k) return; stage.keysHeld[k] = false; call("onKeyUp", k); }
    function point(x, y, down) {
        stage.mouseState.x = x;
        stage.mouseState.y = y;
        if (down !== undefined) stage.mouseState.down = down;
    }
    function tap(x, y) { point(x, y); call("onClick", x, y); }

    Rectangle { anchors.fill: parent; color: "black" }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative
        onPaint: {
            if (!stage.prog) return;
            getContext("2d");
            stage.call("frame", (Date.now() - stage.t0) / 1000);
        }
    }

    FrameAnimation {
        running: stage.running
        onTriggered: canvas.requestPaint()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: function(m) { stage.point(m.x, m.y); }
        onPressed: function(m) { stage.point(m.x, m.y, true); }
        onReleased: function(m) { stage.point(m.x, m.y, false); }
        onClicked: function(m) { stage.tap(m.x, m.y); }
    }

    Keys.onPressed: function(e) {
        e.accepted = true;
        if (e.key === Qt.Key_Escape) { stage.stop(); return; }
        if (!e.isAutoRepeat) stage.press(stage.keyName(e));
    }
    Keys.onReleased: function(e) {
        e.accepted = true;
        if (!e.isAutoRepeat) stage.release(stage.keyName(e));
    }

    // the one way out besides Esc — everything else belongs to the program
    Rectangle {
        id: stopBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width: stopLabel.implicitWidth + 26
        height: 32
        radius: 16
        color: stopHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.1)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.35)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: stopLabel
            anchors.centerIn: parent
            text: "■  stop"
            font.family: w.fontFamily
            font.pixelSize: 13
            color: "white"
        }
        HoverHandler { id: stopHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: stage.stop()
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 18
        text: "▶ your code, running   ·   the keys and the mouse are its   ·   esc or ■ stop to come back"
        font.family: w.fontFamily
        font.pixelSize: 12
        color: "white"
        opacity: 0.45
    }
}
