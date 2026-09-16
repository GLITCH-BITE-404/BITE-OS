// One letter on the page. Positioned by grid cell, never re-created when it
// moves — only re-placed, which is what lets it slide.
//
// All entrance styles share one set of animations whose from/to/easing are
// filled in when the letter is born. Thousands of letters each carrying six
// separate style animations would be thousands of idle objects for nothing.

import QtQuick

Text {
    id: g
    property var w
    property int col: 0
    property int row: 0
    property string glyph: ""
    property int born: 0
    property bool bad: false          // CODE / LYRICS: not what the ghost says
    property int cells: 1             // 2 for Chinese, Japanese, Korean, emoji
    property bool rtlFont: false      // Hebrew / Arabic: drawn in a font that has them

    property bool live: false
    property real rise: 0
    property real dx: 0
    property real bump: 0
    property real scr: 1              // glitch scramble, 0 → 1
    property real heat: 0             // accent flash, 1 → 0
    property real jit: 0              // 1 while a glitch entrance shakes it

    x: w.padX + col * w.slot
    y: row * w.lineH
    width: w.charW * cells + (cells - 1)
    height: w.lineH
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: scr < 1 ? w.noise(scr) : glyph
    font.family: rtlFont && w.fontRtl ? w.fontRtl : w.fontFamily
    font.pixelSize: w.fontPx
    readonly property color ink: w.colour === "rainbow"
        ? Qt.hsla(((col * 0.031 + row * 0.113) % 1 + 1) % 1, 0.72, 0.7, 1)
        : (w.colour === "accent" ? w.cAccent : w.cText)
    color: g.bad ? w.cBad : (g.heat > 0.001 ? w.mix(g.ink, w.cAccent, g.heat) : g.ink)
    transform: Translate { x: g.dx; y: g.rise + g.bump }

    Behavior on x {
        enabled: g.live && g.w.near(g.row)
        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }
    Behavior on y {
        enabled: g.live && g.w.near(g.row)
        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }

    SequentialAnimation {
        id: enter
        PauseAnimation { id: wait; duration: 0 }
        ParallelAnimation {
            NumberAnimation { id: aScale; target: g; property: "scale" }
            NumberAnimation { id: aRise; target: g; property: "rise" }
            NumberAnimation { id: aOp; target: g; property: "opacity" }
            NumberAnimation { id: aSpin; target: g; property: "rotation" }
            NumberAnimation { id: aScr; target: g; property: "scr" }
            NumberAnimation { id: aHeat; target: g; property: "heat"; to: 0 }
            SequentialAnimation {
                // zero distances rather than zero loops: every style runs it,
                // only glitch makes it move
                NumberAnimation { target: g; property: "dx"; to: 4 * g.jit; duration: 40 }
                NumberAnimation { target: g; property: "dx"; to: -3 * g.jit; duration: 40 }
                NumberAnimation { target: g; property: "dx"; to: 2 * g.jit; duration: 40 }
                NumberAnimation { target: g; property: "dx"; to: 0; duration: 60 }
            }
        }
    }

    function set(a, from, to, ms, type, ov) {
        a.from = from; a.to = to; a.duration = ms; a.easing.type = type;
        if (ov !== undefined) a.easing.overshoot = ov;
    }

    function play(style) {
        var ov = w.overshoot, r = Math.random() - 0.5;
        // defaults: every property already at rest, 1ms, so unused parts are inert
        set(aScale, 1, 1, 1, Easing.Linear); set(aRise, 0, 0, 1, Easing.Linear);
        set(aOp, 0, 1, 120, Easing.OutCubic); set(aSpin, 0, 0, 1, Easing.Linear);
        set(aScr, 1, 1, 1, Easing.Linear);
        aHeat.from = w.colour === "flash" ? 1 : 0; aHeat.duration = w.colour === "flash" ? 650 : 1;
        g.jit = style === "glitch" ? 1 : 0;

        switch (style) {
        case "drop":
            set(aRise, -w.lineH * 1.3, 0, 560, Easing.OutBounce);
            set(aOp, 0, 1, 90, Easing.OutCubic);
            break;
        case "glitch":
            set(aScr, 0, 1, 220, Easing.Linear);
            set(aOp, 0, 1, 50, Easing.Linear);
            aHeat.from = 1; aHeat.duration = 380;
            break;
        case "stamp":
            set(aScale, 2.4, 1, 280, Easing.OutQuint);
            set(aSpin, r * 26, 0, 380, Easing.OutBack, 2);
            set(aOp, 0, 1, 110, Easing.OutCubic);
            break;
        case "spin":
            set(aScale, 0, 1, 480, Easing.OutBack, ov);
            set(aSpin, r < 0 ? -220 : 220, 0, 480, Easing.OutBack, 1.2);
            break;
        case "float":
            set(aScale, 0.85, 1, 700, Easing.OutQuint);
            set(aRise, 26, 0, 700, Easing.OutQuint);
            set(aOp, 0, 1, 520, Easing.InOutSine);
            break;
        default:        // launcher — reusables/Input.qml's add transition
            set(aScale, 0.3, 1, 420, Easing.OutBack, ov);
            set(aRise, 10, 0, 420, Easing.OutBack, ov * 0.8);
            set(aOp, 0, 1, 140, Easing.OutCubic);
        }
        g.scale = aScale.from; g.rise = aRise.from; g.opacity = 0;
        g.rotation = aSpin.from; g.scr = aScr.from; g.heat = aHeat.from;
        wait.duration = g.born;
        enter.start();
    }

    // the ripple: a letter further along the line landed, and this one feels it
    SequentialAnimation {
        id: kickAnim
        PauseAnimation { id: kickWait; duration: 0 }
        NumberAnimation { target: g; property: "bump"; to: -7; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: g; property: "bump"; to: 0; duration: 300; easing.type: Easing.OutBounce }
    }
    function kick(delay, strength) {
        kickWait.duration = delay;
        kickAnim.restart();
    }

    // a wrong letter shudders once when it goes red
    SequentialAnimation {
        id: shudder
        NumberAnimation { target: g; property: "dx"; to: -3; duration: 40 }
        NumberAnimation { target: g; property: "dx"; to: 3; duration: 40 }
        NumberAnimation { target: g; property: "dx"; to: 0; duration: 60 }
    }
    onBadChanged: if (bad && live) shudder.restart()

    // a party trick for when code compiles or a song is finished
    SequentialAnimation {
        id: cheer
        PauseAnimation { id: cheerWait; duration: 0 }
        NumberAnimation { target: g; property: "bump"; to: -18; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: g; property: "bump"; to: 0; duration: 520; easing.type: Easing.OutBounce }
    }
    function celebrate(delay) { cheerWait.duration = delay; cheer.restart(); }

    Component.onCompleted: {
        if (w.near(row)) {
            play(w.entrance === "random" ? w.randomStyle() : w.entrance);
        } else {
            g.scale = 1; g.opacity = 1;          // off screen: nobody would see it land
        }
        live = true;
    }
}
