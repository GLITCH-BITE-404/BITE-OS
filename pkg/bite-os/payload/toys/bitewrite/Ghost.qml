// A deleted letter's stand-in. The real one is gone the moment the model drops
// it, so this plays the exit where it stood and then destroys itself.

import QtQuick

Text {
    id: gh
    property var w
    property string style: "launcher"
    property string glyph: ""
    property real rise: 0
    property real dx: 0
    property real scr: 1

    width: w.charW
    height: w.lineH
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: w.fontFamily
    font.pixelSize: w.fontPx
    text: scr < 1 ? w.noise(scr) : glyph
    transform: Translate { x: gh.dx; y: gh.rise }

    ParallelAnimation {
        id: out
        NumberAnimation { id: aScale; target: gh; property: "scale" }
        NumberAnimation { id: aRise; target: gh; property: "rise" }
        NumberAnimation { id: aDx; target: gh; property: "dx" }
        NumberAnimation { id: aSpin; target: gh; property: "rotation" }
        SequentialAnimation {
            PauseAnimation { id: aHold; duration: 0 }
            NumberAnimation { id: aOp; target: gh; property: "opacity"; to: 0 }
        }
        NumberAnimation { id: aScr; target: gh; property: "scr" }
        onFinished: gh.destroy()
    }

    function set(a, to, ms, type, ov) {
        a.to = to; a.duration = ms; a.easing.type = type;
        if (ov !== undefined) a.easing.overshoot = ov;
    }

    Component.onCompleted: {
        var r = Math.random() - 0.5, side = r < 0 ? -1 : 1;
        set(aScale, gh.scale, 1, Easing.Linear); set(aRise, gh.rise, 1, Easing.Linear);
        set(aDx, 0, 1, Easing.Linear); set(aSpin, gh.rotation, 1, Easing.Linear);
        set(aScr, 1, 1, Easing.Linear); aHold.duration = 0;
        switch (style) {
        case "fall":
            set(aRise, w.lineH * (4 + Math.random() * 4), 760, Easing.InQuad);
            set(aDx, r * 90, 760, Easing.OutQuad);
            set(aSpin, side * (70 + Math.random() * 120), 760, Easing.InQuad);
            aHold.duration = 420; set(aOp, 0, 340, Easing.InCubic);
            break;
        case "dust":
            set(aScale, 1.5, 200, Easing.OutCubic);
            set(aOp, 0, 200, Easing.OutCubic);
            break;
        case "flick":
            set(aDx, side * (140 + Math.random() * 120), 320, Easing.OutCubic);
            set(aRise, -(30 + Math.random() * 60), 320, Easing.OutCubic);
            set(aSpin, side * 100, 320, Easing.OutCubic);
            set(aOp, 0, 320, Easing.InCubic);
            break;
        case "glitch":
            gh.scr = 0.01;
            set(aScr, 0.99, 200, Easing.Linear);
            set(aDx, r * 16, 200, Easing.OutBounce);
            aHold.duration = 120; set(aOp, 0, 80, Easing.Linear);
            gh.color = w.cAccent;
            break;
        default:        // launcher — reusables/Input.qml's remove transition
            set(aScale, 0.3, 160, Easing.InBack);
            set(aRise, gh.rise - 8, 160, Easing.InCubic);
            set(aOp, 0, 144, Easing.InCubic);
        }
        out.start();
    }
}
