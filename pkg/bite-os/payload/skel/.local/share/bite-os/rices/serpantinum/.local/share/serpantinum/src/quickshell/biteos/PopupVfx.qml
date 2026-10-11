// BITE-OS: glitch VFX for a frame (a popup or an app window), click-through.
// Styles (BiteStyle.popupFx / windowFx):
//   blast   - RGB-split outline blasting OUTWARD, slivers, corner brackets
//             (needs room around the frame: popups)
//   reticle - INSIDE: target ring locks on the centre, crosshairs, inner
//             corner brackets, the label decrypts under it
//   scan    - INSIDE: neon scan bar sweeps down with an RGB fringe
//   hex     - INSIDE: hex characters burst out of the centre
import QtQuick
import "../"

Item {
    id: root
    enabled: false
    property rect frame: Qt.rect(0, 0, 0, 0)
    property real radius: 12
    property real sc: 1.0
    property string style: "blast"
    property string label: ""
    function s(v) { return v * root.sc; }

    readonly property color cRed: "#ff2a6d"
    readonly property color cCyan: "#00f0ff"
    readonly property color cNeon: "#39ff14"
    readonly property real cx: frame.x + frame.width / 2
    readonly property real cy: frame.y + frame.height / 2
    property real progress: 1.0
    property real jitter: 0
    property real power: 1.0
    property string activeStyle: style
    readonly property bool running: burstAnim.running

    function fire(strength) {
        if (!BiteStyle.glitchOn || frame.width < 10) return;
        root.activeStyle = root.style;
        root.power = (strength === undefined ? 1.0 : strength) * (BiteStyle.glitchLoud ? 1.5 : 1.0);
        // only prepare the pieces the chosen style draws; pieces are created
        // once and just re-randomised (recreating them cost 9-33ms per open)
        if (root.activeStyle === "blast") root.blastSeed = Math.random() * 100.0;
        else if (root.activeStyle === "hex") hexes.reseed();
        else if (root.activeStyle === "reticle") labelText.decodeTo(root.label);
        burstAnim.restart();
    }

    NumberAnimation {
        id: burstAnim
        target: root; property: "progress"
        from: 0; to: 1
        duration: (root.activeStyle === "blast" ? 480 : 700) * (BiteStyle.glitchLoud ? 1.3 : 1.0)
        easing.type: Easing.OutCubic
    }
    Timer {
        interval: 40; repeat: true; running: root.running
        onTriggered: root.jitter = (Math.random() - 0.5) * 2
    }

    // ═══ BLAST (outside) ═══════════════════════════════════════════════
    // one shader pass (shaders/biteos/blast.frag) instead of ~25 items that
    // were re-tessellated every frame; quad = frame + sliver room left/right
    property real blastSeed: 0
    ShaderEffect {
        id: blastFx
        visible: root.running && root.activeStyle === "blast"
        // wide only where slivers fly (left/right); just the outline's growth above/below
        readonly property real marginX: root.s(410) * root.power
        readonly property real marginY: root.s(50) * root.power
        x: root.frame.x - marginX; y: root.frame.y - marginY
        width: root.frame.width + marginX * 2; height: root.frame.height + marginY * 2
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector4d frame: Qt.vector4d(marginX, marginY, root.frame.width, root.frame.height)
        property real progress: root.progress
        property real power: root.power
        property real jitter: root.jitter
        property real radius: root.radius
        property real seed: root.blastSeed
        property real count: BiteStyle.glitchLoud ? 11 : 8   // lanes per side (cost is O(1) per pixel)
        property real scale: root.sc
        property color colRed: root.cRed
        property color colCyan: root.cCyan
        property color colMauve: ThemeBackend.mauve
        fragmentShader: "file://" + BiteStyle.shaderDir + "/blast.frag.qsb"
    }

    // corner brackets for reticle (inner corners); blast draws its own
    Repeater {
        model: 4
        delegate: Item {
            id: corner
            required property int index
            readonly property bool atRight: index === 1 || index === 2
            readonly property bool atBottom: index >= 2
            readonly property real slam: Math.max(0, 1.0 - root.progress * 3.0)
            readonly property real off: root.s(36) * root.power * slam
            readonly property real arm: root.s(root.activeStyle === "reticle" ? 34 : 26)
            readonly property real inset: root.activeStyle === "reticle" ? root.s(18) : root.s(-6)
            visible: root.running && root.activeStyle === "reticle"
            width: arm; height: arm
            x: (atRight ? root.frame.x + root.frame.width - arm - inset + off : root.frame.x + inset - off)
            y: (atBottom ? root.frame.y + root.frame.height - arm - inset + off : root.frame.y + inset - off)
            opacity: root.progress < 0.6 ? 1.0 : (1.0 - root.progress) / 0.4
            Rectangle { width: parent.width; height: root.s(3); color: root.cCyan; y: corner.atBottom ? parent.height - height : 0 }
            Rectangle { width: root.s(3); height: parent.height; color: root.cCyan; x: corner.atRight ? parent.width - width : 0 }
        }
    }

    // ═══ RETICLE (inside, centre) ════════════════════════════════════════
    Item {
        visible: root.running && root.activeStyle === "reticle"
        anchors.fill: parent
        readonly property real maxR: Math.min(root.frame.width, root.frame.height) * 0.22
        // lock-on: ring shrinks from big onto its final size, then fades
        readonly property real lock: Math.min(1, root.progress / 0.35)
        readonly property real ringR: maxR * (1.8 - 0.8 * lock)
        readonly property real fade: root.progress < 0.65 ? 1.0 : (1.0 - root.progress) / 0.35
        id: reticle

        Repeater {
            model: [{ c: root.cRed, k: -1 }, { c: root.cCyan, k: 1 }, { c: "#ffffff", k: 0 }]
            delegate: Rectangle {
                required property var modelData
                width: reticle.ringR * 2; height: width; radius: width / 2
                x: root.cx - width / 2 + modelData.k * root.s(4) * root.jitter * (1 - reticle.lock * 0.7)
                y: root.cy - height / 2
                color: "transparent"
                border.width: Math.max(1, root.s(modelData.k === 0 ? 2 : 1.5))
                border.color: modelData.c
                opacity: reticle.fade * (modelData.k === 0 ? 0.9 : 0.7)
            }
        }
        // inner dashed ring: 12 ticks rotating while it locks
        Repeater {
            model: 12
            delegate: Rectangle {
                required property int index
                readonly property real a: index / 12 * Math.PI * 2 + (1 - reticle.lock) * 2.2
                width: root.s(3); height: root.s(10)
                x: root.cx + Math.cos(a) * reticle.ringR * 0.72 - width / 2
                y: root.cy + Math.sin(a) * reticle.ringR * 0.72 - height / 2
                rotation: a * 180 / Math.PI + 90
                color: root.cCyan
                opacity: reticle.fade * 0.8
            }
        }
        // crosshairs sliding in to the ring
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                readonly property bool horiz: index < 2
                readonly property int dir: index % 2 ? 1 : -1
                readonly property real gap: reticle.ringR * (1.05 + (1 - reticle.lock) * 1.2)
                readonly property real len: root.s(46)
                width: horiz ? len : root.s(2)
                height: horiz ? root.s(2) : len
                x: horiz ? (dir < 0 ? root.cx - gap - len : root.cx + gap) : root.cx - width / 2
                y: horiz ? root.cy - height / 2 : (dir < 0 ? root.cy - gap - len : root.cy + gap)
                color: "#ffffff"
                opacity: reticle.fade * 0.85
            }
        }
        Rectangle {   // centre dot
            width: root.s(6); height: width; radius: width / 2
            x: root.cx - width / 2; y: root.cy - height / 2
            color: root.cRed
            opacity: reticle.lock >= 1 ? reticle.fade : 0
        }
    }

    // label (reticle): decrypts under the ring
    Text {
        id: labelText
        visible: root.running && root.activeStyle === "reticle" && root.label !== ""
        x: root.cx - width / 2
        y: root.cy + Math.min(root.frame.width, root.frame.height) * 0.22 * 1.05 + root.s(58)
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: root.s(15)
        font.bold: true
        color: root.cNeon
        opacity: root.progress < 0.65 ? 1.0 : (1.0 - root.progress) / 0.35
        property string target: ""
        property int resolved: 0
        function decodeTo(t) { target = t; resolved = 0; text = ""; decodeTimer.restart(); }
        Timer {
            id: decodeTimer
            interval: 24; repeat: true
            onTriggered: {
                let g = "!<>-_/[]{}=+*^?#0123456789ABCDEF";
                labelText.resolved += Math.max(1, Math.ceil(labelText.target.length / 14));
                let out = labelText.target.substring(0, labelText.resolved);
                for (let i = labelText.resolved; i < labelText.target.length; i++)
                    out += labelText.target[i] === " " ? " " : g[Math.floor(Math.random() * g.length)];
                labelText.text = out;
                if (labelText.resolved >= labelText.target.length) stop();
            }
        }
    }

    // ═══ SCAN (inside) ═══════════════════════════════════════════════════
    Item {
        id: scan
        visible: root.running && root.activeStyle === "scan"
        x: root.frame.x; y: root.frame.y
        width: root.frame.width; height: root.frame.height
        clip: true
        readonly property real barY: -root.s(20) + (height + root.s(40)) * root.progress
        // inner edge flash
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.width: root.s(2)
            border.color: root.cCyan
            opacity: Math.max(0, 1.0 - root.progress * 2.5)
        }
        // trail
        Rectangle {
            width: parent.width; height: root.s(140)
            y: scan.barY - height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha(root.cCyan, 0.22) }
            }
            opacity: 1.0 - root.progress * 0.6
        }
        // the bar + RGB fringe
        Repeater {
            model: [{ c: root.cRed, dy: -3 }, { c: root.cCyan, dy: 3 }, { c: "#ffffff", dy: 0 }]
            delegate: Rectangle {
                required property var modelData
                width: scan.width
                height: root.s(modelData.dy === 0 ? 3 : 2)
                y: scan.barY + root.s(modelData.dy) * (1 + root.jitter)
                color: modelData.c
                opacity: (1.0 - root.progress * 0.5) * (modelData.dy === 0 ? 1 : 0.8)
            }
        }
        // a few torn slivers riding the bar
        Repeater {
            model: 6
            delegate: Rectangle {
                required property int index
                width: scan.width * (0.08 + ((index * 37) % 23) / 100)
                height: root.s(2 + index % 3)
                x: ((index * 173) % 97) / 97 * scan.width + root.jitter * root.s(30)
                y: scan.barY - root.s(6 + index * 9)
                color: [root.cRed, root.cCyan, ThemeBackend.mauve][index % 3]
                opacity: 0.7 * (1.0 - root.progress)
            }
        }
    }

    // ═══ HEX (inside, centre) ════════════════════════════════════════════
    Item {
        id: hexes
        visible: root.running && root.activeStyle === "hex"
        anchors.fill: parent
        property var seeds: []
        function reseed() {
            let n = BiteStyle.glitchLoud ? 54 : 36, out = [], h = "0123456789ABCDEF";
            for (let i = 0; i < n; i++)
                out.push({ a: Math.random() * Math.PI * 2, d: 0.25 + Math.random() * 0.75,
                           t: h[Math.floor(Math.random() * 16)] + h[Math.floor(Math.random() * 16)],
                           c: [root.cNeon, root.cCyan, root.cRed, "#ffffff"][i % 4], size: 12 + Math.random() * 14 });
            seeds = out;
        }
        Repeater {
            model: hexes.seeds.length
            delegate: Text {
                required property int index
                readonly property var modelData: hexes.seeds[index]
                readonly property real reach: Math.min(root.frame.width, root.frame.height) * 0.48 * modelData.d * root.progress * root.power
                text: modelData.t
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.s(modelData.size)
                font.bold: true
                color: modelData.c
                x: root.cx + Math.cos(modelData.a) * reach - width / 2
                y: root.cy + Math.sin(modelData.a) * reach - height / 2
                opacity: root.progress < 0.15 ? root.progress / 0.15 : 1.0 - (root.progress - 0.15) / 0.85
            }
        }
        Rectangle {   // core flash
            width: root.s(90) * (0.3 + root.progress); height: width; radius: width / 2
            x: root.cx - width / 2; y: root.cy - height / 2
            color: "transparent"
            border.width: root.s(2)
            border.color: root.cNeon
            opacity: Math.max(0, 1.0 - root.progress * 2.0)
        }
    }
}
