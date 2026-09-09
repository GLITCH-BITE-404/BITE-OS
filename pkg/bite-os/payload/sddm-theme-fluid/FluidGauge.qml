// Liquid-fill gauge card. Same technique as the Serpantinum lock screen:
// a bezier surface driven by a shared phase, clipped to a rounded card,
// vertical gradient. One shared phase keeps every gauge in sync and each
// card repaints only while it is actually on screen.
import QtQuick

Item {
    id: g

    property string label: ""
    property string valueText: ""
    property real level: 0.0          // 0..1
    property color fillCol: "#b48aff"
    property color textCol: "#cdd6f4"
    property color subCol: "#6c7086"
    property color cardCol: "#181825"
    property color borderCol: "#313244"
    property string mono: "monospace"
    property real wavePhase: 0.0
    property real scaleF: 1.0
    property bool live: true          // false => don't repaint on phase
    property bool hoverable: false
    signal clicked()

    function s(v) { return Math.round(v * g.scaleF) }

    implicitWidth: s(136)
    implicitHeight: s(62)

    readonly property real cardRadius: s(12)
    // ease the level so a jumpy reading still glides
    property real animLevel: 0.0
    Behavior on animLevel { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
    onLevelChanged: animLevel = Math.max(0, Math.min(1, level))
    Component.onCompleted: animLevel = Math.max(0, Math.min(1, level))

    // outer glow ring, tinted by whatever the gauge measures
    Rectangle {
        anchors.fill: parent
        anchors.margins: -g.s(3)
        radius: g.cardRadius + g.s(3)
        color: "transparent"
        border.width: 1
        border.color: g.fillCol
        opacity: g.glowPulse
        property real glowPulse: 0.16
        SequentialAnimation on glowPulse {
            loops: Animation.Infinite
            running: g.live
            NumberAnimation { to: 0.42; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.14; duration: 1600; easing.type: Easing.InOutSine }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: g.cardRadius
        color: g.cardCol
        opacity: 0.78
        border.width: 1
        border.color: Qt.rgba(g.fillCol.r, g.fillCol.g, g.fillCol.b,
                              gaugeMa.containsMouse ? 1.0 : 0.55)
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Immediate

        readonly property real fillY: height * (1.0 - g.animLevel)
        readonly property real waveAmp: g.animLevel > 0.01 ? g.s(4) : 0

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (g.animLevel <= 0.001) return

            ctx.save()
            var r = g.cardRadius
            ctx.beginPath()
            ctx.moveTo(r, 0)
            ctx.lineTo(width - r, 0)
            ctx.quadraticCurveTo(width, 0, width, r)
            ctx.lineTo(width, height - r)
            ctx.quadraticCurveTo(width, height, width - r, height)
            ctx.lineTo(r, height)
            ctx.quadraticCurveTo(0, height, 0, height - r)
            ctx.lineTo(0, r)
            ctx.quadraticCurveTo(0, 0, r, 0)
            ctx.closePath()
            ctx.clip()

            ctx.beginPath()
            ctx.moveTo(0, fillY)
            var sinP = Math.sin(g.wavePhase)
            var cosP = Math.cos(g.wavePhase + Math.PI)
            ctx.bezierCurveTo(width * 0.33, fillY + cosP * waveAmp,
                              width * 0.66, fillY + sinP * waveAmp,
                              width, fillY)
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()

            var grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.lighter(g.fillCol, 1.18).toString())
            grad.addColorStop(1, g.fillCol.toString())
            ctx.fillStyle = grad
            ctx.globalAlpha = 0.46
            ctx.fill()
            ctx.restore()
        }

        Connections {
            target: g
            enabled: g.live
            function onWavePhaseChanged() { canvas.requestPaint() }
            function onAnimLevelChanged() { canvas.requestPaint() }
            function onFillColChanged()  { canvas.requestPaint() }
        }
    }

    MouseArea {
        id: gaugeMa
        anchors.fill: parent
        enabled: g.hoverable
        hoverEnabled: g.hoverable
        cursorShape: g.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: g.clicked()
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: g.s(12)
        anchors.rightMargin: g.s(12)
        spacing: g.s(1)

        Text {
            text: g.label
            font.family: g.mono
            font.pixelSize: g.s(10)
            font.letterSpacing: g.s(2)
            color: g.fillCol
        }
        Text {
            text: g.valueText
            font.family: g.mono
            font.pixelSize: g.s(17)
            color: g.textCol
        }
    }
}
