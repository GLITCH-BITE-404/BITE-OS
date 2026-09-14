// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Desktop widget: matrix rain. The Binary and Glitch looks
//  are thin files that reuse this one with different settings.
//
//  60fps budget: each column is ONE item whose y is animated, so a frame is
//  just a transform per column. Glyphs change imperatively on one shared timer
//  (~75 swaps/s), never through per-frame bindings. Glitch mode adds one ghost
//  glyph per column and a second slow timer. Columns are capped, and
//  everything stops while hidden. Katakana come from noto-fonts-cjk, which the
//  ISO ships.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import Quickshell
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 140
    property real minHeight: 110
    property real maxWidth: 1400
    property real maxHeight: 1000
    property real minAspect: 0.25
    property real maxAspect: 5.0
    property bool isRound: false

    // ── look (overridden by the variant files) ──────────────────────────────
    property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:=*+<>"
    property string glyphFont: "Noto Sans CJK JP"
    property color cHead: ThemeBackend.text
    property color cTrail: ThemeBackend.green
    property bool glitch: false

    readonly property real cell: Scaler.s(15)
    readonly property int cols: Math.min(90, Math.max(1, Math.floor(width / cell)))
    function randomGlyph() { return glyphs.charAt(Math.floor(Math.random() * glyphs.length)); }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.9)
    }

    Item {
        anchors.fill: parent
        clip: true

        Repeater {
            id: columns
            model: root.cols

            Item {
                id: col
                required property int index
                property int tailLen: 6 + Math.floor(Math.random() * 14)
                // glitch mode: a short sideways jolt with a red or blue tint
                property real jolt: 0
                property color tint: "transparent"

                x: index * root.cell
                y: -height
                width: root.cell
                height: tailLen * root.cell
                transform: Translate { x: col.jolt }

                function flick() {
                    let t = trail.itemAt(Math.floor(Math.random() * col.tailLen));
                    if (t) t.text = root.randomGlyph();
                }
                function strike() {
                    col.jolt = (Math.random() < 0.5 ? -1 : 1) * root.cell * (0.25 + Math.random() * 0.35);
                    col.tint = Math.random() < 0.5 ? ThemeBackend.red : ThemeBackend.blue;
                    settle.restart();
                }
                Timer {
                    id: settle
                    interval: 90
                    onTriggered: { col.jolt = 0; col.tint = "transparent"; }
                }

                SequentialAnimation {
                    running: root.visible
                    PauseAnimation { duration: Math.floor(Math.random() * 4000) }
                    NumberAnimation {
                        target: col
                        property: "y"
                        from: -col.height
                        to: root.height
                        duration: 2200 + Math.floor(Math.random() * 4200)
                        loops: Animation.Infinite
                    }
                }

                // RGB-split ghost behind the head (glitch look only). Reading
                // .text off the head item keeps it in step with flick().
                Text {
                    visible: root.glitch
                    x: Math.round(root.cell * 0.12)
                    y: (col.tailLen - 1) * root.cell
                    width: root.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: (root.glitch && trail.count === col.tailLen && trail.itemAt(col.tailLen - 1))
                          ? trail.itemAt(col.tailLen - 1).text : ""
                    font.family: root.glyphFont
                    font.pixelSize: Math.round(root.cell * 0.85)
                    color: ThemeBackend.red
                    opacity: 0.55
                }

                Repeater {
                    id: trail
                    model: col.tailLen
                    Text {
                        required property int index
                        readonly property bool isHead: index === col.tailLen - 1
                        y: index * root.cell
                        width: root.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: root.randomGlyph()
                        font.family: root.glyphFont
                        font.pixelSize: Math.round(root.cell * 0.85)
                        color: col.tint.a > 0 ? col.tint : (isHead ? root.cHead : root.cTrail)
                        opacity: isHead ? 1.0 : (0.12 + 0.78 * index / col.tailLen)
                    }
                }
            }
        }
    }

    // one shared timer swaps a few random glyphs; no per-frame work
    Timer {
        interval: 80
        repeat: true
        running: root.visible && columns.count > 0
        onTriggered: {
            for (let k = 0; k < 6; k++) {
                let c = columns.itemAt(Math.floor(Math.random() * columns.count));
                if (c) c.flick();
            }
        }
    }

    // glitch look: now and then one column jolts
    Timer {
        interval: 160
        repeat: true
        running: root.visible && root.glitch && columns.count > 0
        onTriggered: {
            if (Math.random() < 0.45) {
                let c = columns.itemAt(Math.floor(Math.random() * columns.count));
                if (c) c.strike();
            }
        }
    }
}
