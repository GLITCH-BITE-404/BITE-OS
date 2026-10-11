// BITE-OS: drop inside any Item and call burst() to glitch it for a moment
// (RGB split + slice tear). The host only renders through the shader while
// a burst runs, so at rest it costs nothing. Respects BiteStyle.glitch.
import QtQuick
import "../"

Item {
    id: root
    property Item target: parent
    // wait this long before bursting (lets a fading-in popup become visible first)
    property int delay: 0
    // loud mode: random flickers while the target is visible
    property bool flicker: false
    property real amount: 0
    property real seed: 0
    property real peak: 1.0
    visible: false

    // strength 0..1 (default 1), wait in ms (default: delay)
    function burst(strength, wait) {
        if (!BiteStyle.glitchOn || !root.target) return;
        root.peak = BiteStyle.glitchPeak * (strength === undefined ? 1.0 : strength);
        let w = wait === undefined ? root.delay : wait;
        if (w > 0) { delayTimer.interval = w; delayTimer.restart(); } else steps.restart();
    }

    Timer { id: delayTimer; onTriggered: steps.restart() }

    // stepped, not smooth: digital glitches jump between levels
    SequentialAnimation {
        id: steps
        readonly property int t: Math.max(20, BiteStyle.glitchDuration / 5)
        PropertyAction { target: root; property: "amount"; value: root.peak }
        PauseAnimation { duration: steps.t }
        PropertyAction { target: root; property: "amount"; value: root.peak * 0.35 }
        PauseAnimation { duration: steps.t }
        PropertyAction { target: root; property: "amount"; value: root.peak * 0.85 }
        PauseAnimation { duration: steps.t }
        PropertyAction { target: root; property: "amount"; value: root.peak * 0.2 }
        PauseAnimation { duration: steps.t }
        NumberAnimation { target: root; property: "amount"; to: 0; duration: steps.t }
    }

    Timer {
        interval: 45
        repeat: true
        running: root.amount > 0.001
        onTriggered: root.seed = Math.random() * 100.0
    }

    Timer {
        id: flickerTimer
        repeat: true
        interval: 4000
        running: root.flicker && BiteStyle.glitchLoud && root.target && root.target.visible
        onTriggered: {
            interval = 2500 + Math.random() * 4500;
            root.burst(0.5);
        }
    }

    // the host binds: layer.enabled: <this>.active; layer.effect: <this>.effect
    readonly property bool active: amount > 0.001
    readonly property Component effect: glitchEffect

    Component {
        id: glitchEffect
        ShaderEffect {
            property vector2d itemSize: Qt.vector2d(width, height)
            property real amount: root.amount
            property real seed: root.seed
            fragmentShader: "file://" + BiteStyle.shaderDir + "/glitch.frag.qsb"
        }
    }
}
