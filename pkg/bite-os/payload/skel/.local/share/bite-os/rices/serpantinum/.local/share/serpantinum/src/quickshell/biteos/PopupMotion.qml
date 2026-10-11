// BITE-OS: open/close motion for the shell's popups (BiteStyle.popupAnim),
// applied as transforms on the popup frame on top of upstream's own fade.
//   default - upstream only          drop  - falls in from above, bounces
//   zoom    - elastic punch from small   flip - swings down off its top edge
//   unfold  - opens out of a thin line   swing - swings in at an angle, settles
import QtQuick
import "../"

Item {
    id: root
    visible: false
    property real sc: 1.0
    property string style: BiteStyle.popupAnim
    property string activeStyle: style
    // 1 = fully open; open() runs 0 -> 1, close() runs back to 0
    property real t: 1.0
    readonly property real u: 1.0 - t

    function open() {
        root.activeStyle = root.style;
        closeAnim.stop();
        if (root.activeStyle === "default" || !BiteStyle.glitchOn) { root.t = 1.0; return; }
        root.t = 0.0;
        openAnim.easing.type = ({ drop: Easing.OutBack, zoom: Easing.OutBack, flip: Easing.OutBack,
                                   unfold: Easing.OutExpo, swing: Easing.OutBack })[root.activeStyle] || Easing.OutCubic;
        openAnim.easing.overshoot = ({ drop: 1.4, zoom: 2.2, flip: 1.2, swing: 1.6 })[root.activeStyle] || 1.0;
        openAnim.duration = ({ drop: 460, zoom: 420, flip: 520, unfold: 380, swing: 520 })[root.activeStyle] || 400;
        openAnim.restart();
    }
    function close() {
        openAnim.stop();
        if (root.activeStyle === "default" || !BiteStyle.glitchOn) { root.t = 1.0; return; }
        closeAnim.restart();
    }

    NumberAnimation { id: openAnim; target: root; property: "t"; to: 1.0 }
    // upstream fades the popup out over 140ms; finish inside that
    NumberAnimation { id: closeAnim; target: root; property: "t"; to: 0.0; duration: 140; easing.type: Easing.InCubic }

    readonly property bool on: activeStyle !== "default"
    // transform values the host binds (neutral when off)
    readonly property real tx: on && activeStyle === "swing" ? -root.s(70) * u : 0
    readonly property real ty: !on ? 0 : (activeStyle === "drop" ? -root.s(110) * u : 0)
    readonly property real sx: !on ? 1 : (activeStyle === "zoom" ? 0.45 + 0.55 * t : 1)
    readonly property real sy: !on ? 1 : (activeStyle === "zoom" ? 0.45 + 0.55 * t
                                        : (activeStyle === "unfold" ? Math.max(0.012, t) : 1))
    readonly property real angle: !on ? 0 : (activeStyle === "flip" ? -88 * u : (activeStyle === "swing" ? -14 * u : 0))
    readonly property vector3d axis: activeStyle === "flip" ? Qt.vector3d(1, 0, 0) : Qt.vector3d(0, 0, 1)
    // flip hinges on the top edge, swing on the top-left corner
    readonly property bool originTop: activeStyle === "flip" || activeStyle === "swing"
    readonly property bool originLeft: activeStyle === "swing"
    function s(v) { return v * root.sc; }
}
