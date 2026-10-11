// BITE-OS: style settings for BITE-OS's own touches (popup VFX, notification
// effects, lock layer). Stored in ~/.config/serpantinum/bite-style.json,
// edited from the BITE-OS settings tab; missing file = defaults.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    // "off" | "subtle" | "loud"
    property string glitch: "subtle"
    property bool lockLayer: true
    // per-effect styles (each picker in the BITE-OS Style tab)
    property string popupFx: "blast"      // blast | scan | hex
    property string popupAnim: "default"  // default | drop | zoom | flip | unfold | swing (PopupMotion)
    property string notifFx: "bite"       // bite | slice | static | pixel
    property string lockStyle: "dedsec"   // dedsec | matrix   (lockLayer = on/off)
    property string unlockFx: "unzip"     // unzip | crt
    // calm mode: on power saver, decorative desktop widgets (matrix rain,
    // visualizer) freeze into a still frame so popups stay smooth
    property bool calmSaver: true
    readonly property bool powerSaver: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool calm: calmSaver && powerSaver

    readonly property bool glitchOn: glitch === "subtle" || glitch === "loud"
    readonly property bool glitchLoud: glitch === "loud"
    readonly property real glitchPeak: glitch === "loud" ? 1.0 : 0.6
    readonly property int glitchDuration: glitch === "loud" ? 380 : 240
    readonly property string shaderDir: (Quickshell.env("SERPANTINUM_DIR") || "") + "/assets/shaders/biteos"
    readonly property string configPath: Quickshell.env("HOME") + "/.config/serpantinum/bite-style.json"

    function applyText(txt) {
        let o = {};
        try { o = JSON.parse(txt || "{}"); } catch (e) { return; }
        root.glitch = (o.glitch === "off" || o.glitch === "loud") ? o.glitch : "subtle";
        root.lockLayer = o.lockLayer !== false;
        root.popupFx = ["blast", "scan", "hex"].indexOf(o.popupFx) >= 0 ? o.popupFx : "blast";
        root.popupAnim = ["default", "drop", "zoom", "flip", "unfold", "swing"].indexOf(o.popupAnim) >= 0 ? o.popupAnim : "default";
        root.notifFx = ["bite", "slice", "static", "pixel"].indexOf(o.notifFx) >= 0 ? o.notifFx : "bite";
        root.lockStyle = o.lockStyle === "matrix" ? "matrix" : "dedsec";
        root.unlockFx = o.unlockFx === "crt" ? "crt" : "unzip";
        root.calmSaver = o.calmSaver !== false;
    }

    function save(key, value) {
        let o = { glitch: root.glitch, lockLayer: root.lockLayer,
                  popupFx: root.popupFx, popupAnim: root.popupAnim, notifFx: root.notifFx,
                  lockStyle: root.lockStyle, unlockFx: root.unlockFx, calmSaver: root.calmSaver };
        o[key] = value;
        root[key] = value;
        let json = JSON.stringify(o, null, 2);
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"", "sh", json, root.configPath]);
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyText(text())
    }
}
