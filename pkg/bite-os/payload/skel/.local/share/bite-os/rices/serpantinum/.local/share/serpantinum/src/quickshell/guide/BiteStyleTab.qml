// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). BITE-OS's own visual touches: popup VFX, notification
//  bite, window animation, Dedsec lock screen. Stored by BiteStyle.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"
import "../reusables"

Item {
    id: styleTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    component Hint: Text {
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        wrapMode: Text.WordWrap
        font.family: ThemeBackend.fontFamily
        color: ThemeBackend.overlay2
    }

    Flickable {
        anchors.fill: parent
        contentHeight: styleCol.implicitHeight + rootObj.s(20)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: styleCol
        width: parent.width
        spacing: rootObj.s(8)

        Text {
            text: "BITE-OS Style"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: rootObj.s(22)
            color: ThemeBackend.text
        }

        Text {
            Layout.bottomMargin: rootObj.s(8)
            text: "// the system bit you"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
            color: ThemeBackend.subtext0
        }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Intensity"
            options: [{ value: "off", text: "Off" }, { value: "subtle", text: "Subtle" }, { value: "loud", text: "Loud" }]
            current: BiteStyle.glitch
            onPicked: (v) => BiteStyle.save("glitch", v)
        }
        Hint { font.pixelSize: rootObj.s(11); text: "Master switch for every effect below. Loud = bigger and longer." }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Popup effect"
            options: [{ value: "blast", text: "Blast" }, { value: "scan", text: "Scan" }, { value: "hex", text: "Hex" }]
            current: BiteStyle.popupFx
            onPicked: (v) => BiteStyle.save("popupFx", v)
        }
        Hint { font.pixelSize: rootObj.s(11); text: "Blast: outline and slivers explode outward. Scan: a neon bar sweeps through. Hex: hex code bursts from the centre." }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Popup animation"
            options: [{ value: "default", text: "Default" }, { value: "drop", text: "Drop" }, { value: "zoom", text: "Zoom" },
                      { value: "flip", text: "Flip" }, { value: "unfold", text: "Unfold" }, { value: "swing", text: "Swing" }]
            current: BiteStyle.popupAnim
            onPicked: (v) => BiteStyle.save("popupAnim", v)
        }
        Hint { font.pixelSize: rootObj.s(11); text: "How popups move when they open. Drop: falls in and bounces. Zoom: elastic punch from small. Flip: swings down off its top edge. Unfold: opens out of a line. Swing: swings in at an angle." }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Notifications"
            options: [{ value: "bite", text: "Bite" }, { value: "slice", text: "Slice" }, { value: "static", text: "Static" }, { value: "pixel", text: "Pixel" }]
            current: BiteStyle.notifFx
            onPicked: (v) => BiteStyle.save("notifFx", v)
        }
        Hint { font.pixelSize: rootObj.s(11); text: "Bite: jaws slam shut. Slice: strips slide in from both sides. Static: TV static tunes into the card. Pixel: it builds from chunky blocks." }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Lock screen"
            options: [{ value: "plain", text: "Plain" }, { value: "dedsec", text: "Dedsec" }, { value: "matrix", text: "Matrix" }]
            current: BiteStyle.lockLayer ? BiteStyle.lockStyle : "plain"
            onPicked: (v) => {
                BiteStyle.save("lockLayer", v !== "plain");
                if (v !== "plain") BiteStyle.save("lockStyle", v);
            }
        }
        Hint { font.pixelSize: rootObj.s(11); text: "Dedsec: HUD and hex streams on the edges. Matrix: rain across the whole screen. Both glitch the clock." }

        StyleChoice {
            rootObj: styleTabRoot.rootObj
            label: "Unlock"
            options: [{ value: "unzip", text: "Unzip" }, { value: "crt", text: "CRT off" }]
            current: BiteStyle.unlockFx
            onPicked: (v) => BiteStyle.save("unlockFx", v)
        }
        Hint { font.pixelSize: rootObj.s(11); text: "Unzip: the screen tears open from the middle while the HUD decrypts. CRT off: it collapses to a line, then a dot." }
    }
    }
}
