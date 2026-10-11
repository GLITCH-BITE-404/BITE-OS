// BITE-OS: notification entrance/exit effects (BiteStyle.notifFx):
//   bite   - jaws start apart, slam shut, rebound, glitch on impact; tear open on exit
//   slice  - strips slide in from alternating sides; slide back out
//   static - TV static in the card's shape tunes into the card; detunes on exit
//   pixel  - the card assembles from chunky blocks that sharpen into focus
// Shaders in assets/shaders/biteos/{bite,slice,static,pixel}.frag.
// The host binds: layer.enabled: <this>.active; layer.effect: <this>.effect
import QtQuick
import "../"

Item {
    id: root
    property Item target: parent
    property color edgeColor: ThemeBackend.mauve
    property real gap: 0
    property real seed: 0
    property string style: BiteStyle.notifFx
    property string activeStyle: style
    visible: false

    readonly property bool active: gap > 0.001 || glitch.active
    readonly property Component effect: biteEffect
    readonly property int slam: BiteStyle.glitchLoud ? 420 : 340

    property var _done: null

    function enter() {
        if (!BiteStyle.glitchOn) return;
        leaveAnim.stop(); leaveSmooth.stop(); enterSmooth.stop(); enterAnim.stop();
        root.activeStyle = root.style;
        root.gap = 1.0;
        if (root.activeStyle === "bite") enterAnim.restart(); else enterSmooth.restart();
    }

    function leave(done) {
        root._done = done || null;
        if (!BiteStyle.glitchOn) { root.finish(); return; }
        enterAnim.stop(); enterSmooth.stop();
        if (root.activeStyle === "bite") leaveAnim.restart(); else leaveSmooth.restart();
    }

    function finish() {
        let cb = root._done;
        root._done = null;
        if (cb) cb();
    }

    GlitchBurst { id: glitch; target: root.target }

    SequentialAnimation {
        id: enterAnim
        PauseAnimation { duration: 60 }
        NumberAnimation { target: root; property: "gap"; to: 0; duration: root.slam; easing.type: Easing.InQuad }
        ScriptAction { script: glitch.burst(1.0, 0) }
        NumberAnimation { target: root; property: "gap"; to: 0.06; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "gap"; to: 0; duration: 110; easing.type: Easing.InQuad }
    }

    SequentialAnimation {
        id: leaveAnim
        ScriptAction { script: glitch.burst(1.0, 0) }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "gap"; to: 1.0; duration: 300; easing.type: Easing.InBack }
        ScriptAction { script: root.finish() }
    }

    SequentialAnimation {
        id: enterSmooth
        NumberAnimation { target: root; property: "gap"; to: 0; duration: BiteStyle.glitchLoud ? 640 : 520; easing.type: Easing.OutCubic }
        ScriptAction { script: glitch.burst(0.6, 0) }
    }

    SequentialAnimation {
        id: leaveSmooth
        ScriptAction { script: glitch.burst(0.8, 0) }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: root; property: "gap"; to: 1.0; duration: 370; easing.type: Easing.InCubic }
        ScriptAction { script: root.finish() }
    }

    // reshuffle noise/slices while anything is moving
    Timer {
        interval: 40; repeat: true
        running: root.active
        onTriggered: root.seed = Math.random() * 100.0
    }

    Component {
        id: biteEffect
        ShaderEffect {
            property vector2d itemSize: Qt.vector2d(width, height)
            property real gap: root.gap
            property real amount: glitch.amount
            property real seed: root.seed
            property color edgeColor: root.edgeColor
            fragmentShader: "file://" + BiteStyle.shaderDir + "/" + root.activeStyle + ".frag.qsb"
        }
    }
}
