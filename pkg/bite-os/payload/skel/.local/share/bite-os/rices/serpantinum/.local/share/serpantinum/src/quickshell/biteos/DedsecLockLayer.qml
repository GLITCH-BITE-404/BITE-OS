// BITE-OS: Dedsec layer over the lock screen. Purely visual and click-through:
// hex streams down the screen edges, a HUD in the corners, the clock glitches
// every few seconds, a wrong password flashes ACCESS DENIED, unlock flashes
// ACCESS GRANTED. Toggled by BiteStyle.lockLayer (BITE-OS tab).
// Styles: BiteStyle.lockStyle dedsec (hex streams on the edges) | matrix
// (rain across the screen); BiteStyle.unlockFx unzip | crt.
import QtQuick
import Quickshell
import "../"

Item {
    id: root
    anchors.fill: parent
    enabled: false              // never eats input
    visible: BiteStyle.lockLayer
    z: 900

    property bool failed: false
    property bool unlocking: false
    property Item clockTarget: null
    property real sc: 1.0
    function s(v) { return Math.round(v * root.sc); }

    readonly property color neon: "#39ff14"
    readonly property color alarm: "#ff2e4d"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // ── hex streams on the left and right edges ─────────────────────────
    function hexLine(n) {
        let h = "0123456789ABCDEF", out = "";
        for (let i = 0; i < n; i++) out += h[Math.floor(Math.random() * 16)] + (i % 2 ? " " : "");
        return out;
    }

    Repeater {
        model: 2
        delegate: Column {
            id: stream
            required property int index
            visible: BiteStyle.lockStyle === "dedsec"
            x: index === 0 ? root.s(28) : root.width - width - root.s(28)
            y: root.s(70)
            spacing: root.s(2)
            opacity: 0.22
            property var lines: []
            Repeater {
                model: stream.lines
                Text {
                    required property string modelData
                    required property int index
                    text: modelData
                    font.family: root.mono
                    font.pixelSize: root.s(11)
                    color: root.granting ? "#eaffea" : root.neon
                    opacity: 1.0 - index / Math.max(1, stream.lines.length) * 0.7
                    horizontalAlignment: stream.index === 0 ? Text.AlignLeft : Text.AlignRight
                }
            }
            Timer {
                interval: root.granting ? 30 : 140
                repeat: true
                running: root.visible && stream.visible
                triggeredOnStart: true
                onTriggered: {
                    let max = Math.floor((root.height - root.s(140)) / root.s(15));
                    let l = stream.lines.slice();
                    l.unshift(root.hexLine(8));
                    if (l.length > max) l.length = max;
                    stream.lines = l;
                }
            }
        }
    }

    // ── matrix rain (lockStyle: matrix) ─────────────────────────────────
    Item {
        id: rain
        anchors.fill: parent
        visible: BiteStyle.lockStyle === "matrix"
        opacity: 0.32
        readonly property real colW: root.s(20)
        readonly property real lineH: root.s(20)
        readonly property int cols: Math.ceil(width / colW)
        readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789ABCDEF"
        function rnd() { return glyphs[Math.floor(Math.random() * glyphs.length)]; }
        Repeater {
            model: rain.visible ? rain.cols : 0
            delegate: Item {
                id: col
                required property int index
                x: index * rain.colW
                width: rain.colW; height: rain.height
                property real head: -Math.random() * rain.height
                property real speed: root.s(5 + Math.random() * 9)
                property int len: 8 + Math.floor(Math.random() * 16)
                property string trail: ""
                Text {   // dim trail above the head
                    x: 0; y: col.head - col.len * rain.lineH
                    width: rain.colW
                    text: col.trail
                    lineHeightMode: Text.FixedHeight
                    lineHeight: rain.lineH
                    font.family: root.mono
                    font.pixelSize: root.s(15)
                    color: root.neon
                    opacity: 0.55
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {   // bright head
                    x: 0; y: col.head
                    width: rain.colW
                    text: rain.rnd()
                    font.family: root.mono
                    font.pixelSize: root.s(15)
                    font.bold: true
                    color: "#d9ffd0"
                    horizontalAlignment: Text.AlignHCenter
                }
                Timer {
                    interval: 60; repeat: true
                    running: rain.visible && root.visible
                    onTriggered: {
                        col.head += col.speed;
                        if (col.head - col.len * rain.lineH > rain.height) {
                            col.head = -Math.random() * rain.height * 0.5;
                            col.len = 8 + Math.floor(Math.random() * 16);
                        }
                        let t = col.trail.length >= col.len * 2 ? col.trail.substring(2) : col.trail;
                        col.trail = t + rain.rnd() + "\n";
                    }
                }
            }
        }
    }

    // ── corner HUD ──────────────────────────────────────────────────────
    component Hud: Text {
        id: hud
        property string full: ""
        property int shown: 0
        property bool cursorOn: true
        property bool run: true
        text: decoding ? scrambled : full.substring(0, shown) + (shown < full.length || cursorOn ? "_" : "")
        Timer {
            interval: 28
            repeat: true
            running: hud.run && !hud.decoding && hud.shown < hud.full.length
            onTriggered: hud.shown++
        }

        // decrypt into new text: unresolved characters keep scrambling,
        // resolved ones lock in left to right
        property bool decoding: false
        property string target: ""
        property string scrambled: ""
        property int resolved: 0
        function decodeTo(t) { target = t; resolved = 0; decoding = true; decodeTimer.restart(); }
        Timer {
            id: decodeTimer
            interval: 22
            repeat: true
            onTriggered: {
                let glyphs = "!<>-_\\/[]{}=+*^?#0123456789ABCDEF";
                hud.resolved += Math.max(1, Math.ceil(hud.target.length / 12));
                let out = hud.target.substring(0, hud.resolved);
                for (let i = hud.resolved; i < hud.target.length; i++)
                    out += hud.target[i] === " " ? " " : glyphs[Math.floor(Math.random() * glyphs.length)];
                hud.scrambled = out;
                if (hud.resolved >= hud.target.length) {
                    stop();
                    hud.full = hud.target; hud.shown = hud.target.length; hud.decoding = false;
                }
            }
        }
    }

    QtObject { id: blink; property bool on: true }
    Timer { interval: 530; repeat: true; running: root.visible; onTriggered: blink.on = !blink.on }

    Hud {
        id: hudTopLeft
        x: root.s(28); y: root.s(28)
        full: "> BITE-OS // SESSION LOCKED"
        cursorOn: blink.on
        run: root.visible
        font.family: root.mono
        font.pixelSize: root.s(12)
        color: root.neon
        opacity: 0.75
    }
    Hud {
        id: hudTopRight
        anchors.right: parent.right; anchors.rightMargin: root.s(28); y: root.s(28)
        full: "ctOS breach detection: ARMED"
        cursorOn: blink.on
        run: root.visible
        font.family: root.mono
        font.pixelSize: root.s(12)
        color: root.neon
        opacity: 0.75
    }
    Hud {
        id: hudBottom
        x: root.s(28); anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(28)
        full: "> user: " + (Quickshell.env("USER") || "root") + "@bite-os  // awaiting key"
        cursorOn: blink.on
        run: root.visible
        font.family: root.mono
        font.pixelSize: root.s(12)
        color: root.neon
        opacity: 0.75
    }

    // ── slow scan bar ───────────────────────────────────────────────────
    Rectangle {
        id: scanBar
        width: root.width
        height: root.s(90)
        opacity: 0.05
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.85; color: root.neon }
            GradientStop { position: 1.0; color: "transparent" }
        }
        NumberAnimation on y {
            from: -root.s(90); to: root.height
            duration: 5200
            loops: Animation.Infinite
            running: root.visible
        }
    }

    // ── clock glitch every few seconds ──────────────────────────────────
    Timer {
        interval: 5000
        repeat: true
        running: root.visible && root.clockTarget !== null
        onTriggered: {
            interval = 4000 + Math.random() * 5000;
            clockGlitch.burst(0.8, 0);
        }
    }
    GlitchBurst { id: clockGlitch; target: root.clockTarget }
    Binding {
        target: root.clockTarget
        property: "layer.enabled"
        value: clockGlitch.active
        when: root.clockTarget !== null && root.visible
    }
    Binding {
        target: root.clockTarget
        property: "layer.effect"
        value: clockGlitch.effect
        when: root.clockTarget !== null && root.visible
    }

    // ── full-screen flash + banner ──────────────────────────────────────
    Rectangle {
        id: flash
        anchors.fill: parent
        color: root.alarm
        opacity: 0
    }

    Text {
        id: banner
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.16
        font.family: root.mono
        font.pixelSize: root.s(44)
        font.bold: true
        font.letterSpacing: root.s(6)
        opacity: 0
        layer.enabled: bannerGlitch.active
        layer.effect: bannerGlitch.effect
        GlitchBurst { id: bannerGlitch; target: banner }
    }

    SequentialAnimation {
        id: flashAnim
        property color tint: root.alarm
        ScriptAction { script: { flash.color = flashAnim.tint; banner.color = flashAnim.tint; } }
        ParallelAnimation {
            NumberAnimation { target: flash; property: "opacity"; from: 0.22; to: 0; duration: 380; easing.type: Easing.OutQuad }
            NumberAnimation { target: banner; property: "opacity"; to: 1; duration: 60 }
        }
        PauseAnimation { duration: 900 }
        NumberAnimation { target: banner; property: "opacity"; to: 0; duration: 250 }
    }

    function alert(textValue, tint) {
        banner.text = textValue;
        flashAnim.tint = tint;
        flashAnim.restart();
        bannerGlitch.burst(1.0, 0);
        clockGlitch.burst(1.0, 0);
    }

    onFailedChanged: if (failed && visible) alert("ACCESS DENIED", root.alarm)
    // ── ACCESS GRANTED: the screen unzips from the middle ───────────────
    property bool granting: false
    property real zip: 0
    Repeater {
        model: [-1, 1]
        delegate: Item {
            required property var modelData
            visible: root.granting
            width: root.width
            height: root.s(46)
            y: root.height / 2 - height / 2 + modelData * root.zip * root.height / 2
            opacity: 1.0 - Math.max(0, root.zip - 0.7) / 0.3
            Rectangle {
                anchors.centerIn: parent
                width: parent.width; height: parent.height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.neon, 0.35) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle { anchors.centerIn: parent; width: parent.width; height: root.s(3); color: "#eaffea" }
        }
    }
    SequentialAnimation {
        id: grantAnim
        ScriptAction { script: {
            root.granting = true; root.zip = 0;
            hudTopLeft.decodeTo("> KEY ACCEPTED // DECRYPTING");
            hudTopRight.decodeTo("ctOS link: SEVERED");
            hudBottom.decodeTo("> welcome back, " + (Quickshell.env("USER") || "root"));
            clockGlitch.burst(1.0, 0);
        } }
        NumberAnimation { target: root; property: "zip"; to: 1; duration: 480; easing.type: Easing.OutCubic }
    }
    // ── unlockFx: crt — the screen collapses to a line, then a dot ───────
    property real crt: 0     // 0 -> 1
    Item {
        id: crtFx
        anchors.fill: parent
        visible: root.crt > 0
        // squeeze: black closes in from top and bottom to a line
        readonly property real squeeze: Math.min(1, root.crt / 0.45)
        // then the line shrinks to a dot
        readonly property real shrink: Math.max(0, Math.min(1, (root.crt - 0.45) / 0.35))
        readonly property real lineH: Math.max(root.s(3), root.height * (1 - crtFx.squeeze) * 0.5)
        Rectangle { width: parent.width; height: root.height / 2 - crtFx.lineH / 2; color: "black" }
        Rectangle { width: parent.width; height: root.height / 2 - crtFx.lineH / 2; y: root.height - height; color: "black" }
        Rectangle {   // the beam
            readonly property real w: root.width * (1 - crtFx.shrink) + root.s(6)
            width: w; height: crtFx.squeeze >= 1 ? root.s(3) : 0
            x: (root.width - w) / 2; y: root.height / 2 - height / 2
            color: "#eaffea"
            opacity: crtFx.shrink < 1 ? 1 : Math.max(0, 1 - (root.crt - 0.8) / 0.2)
        }
        Rectangle {   // glow dot
            width: root.s(18) * (crtFx.shrink); height: width; radius: width / 2
            x: (root.width - width) / 2; y: (root.height - height) / 2
            color: "#eaffea"
            opacity: crtFx.shrink >= 1 ? Math.max(0, 1 - (root.crt - 0.8) / 0.2) : crtFx.shrink
        }
    }
    NumberAnimation { id: crtAnim; target: root; property: "crt"; from: 0; to: 1; duration: 560; easing.type: Easing.InOutQuad }

    onUnlockingChanged: {
        if (unlocking && visible) {
            if (BiteStyle.unlockFx === "crt") { clockGlitch.burst(1.0, 0); crtAnim.restart(); }
            else grantAnim.restart();
        } else if (!unlocking) { grantAnim.stop(); crtAnim.stop(); granting = false; zip = 0; crt = 0; }
    }
}
