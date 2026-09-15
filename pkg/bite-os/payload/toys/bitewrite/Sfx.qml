// The sound bank. Every sample gets two SoundEffect copies so a fast typist
// overlaps clicks instead of restarting one. Made from a string, so a machine
// without qt6-multimedia still gets a working, silent page instead of a
// window that refuses to load.

import QtQuick

QtObject {
    id: sfx
    property var manifest: ({})
    property string pack: "launcher"
    property real volume: 1.0
    property bool muted: false
    property bool available: true
    property var bank: ({})
    property var made: []
    property int lastKey: -1

    readonly property var info: sfx.manifest[sfx.pack] || null
    readonly property string label: sfx.info ? sfx.info.label : "silent"

    function make(path) {
        if (!sfx.available) return null;
        try {
            var fx = Qt.createQmlObject('import QtMultimedia; SoundEffect {}', sfx, "sfx");
            fx.source = "file://" + encodeURI(path);
            fx.volume = sfx.volume;
            sfx.made.push(fx);
            return fx;
        } catch (e) {
            sfx.available = false;
            console.warn("bitewrite: QtMultimedia missing, writing silently (sudo pacman -S qt6-multimedia)");
            return null;
        }
    }

    function load() {
        for (var i = 0; i < sfx.made.length; i++) sfx.made[i].destroy();
        sfx.made = [];
        var b = {};
        var p = sfx.info;
        if (p) {
            ["key", "space", "enter", "back", "error", "done", "run"].forEach(function(ev) {
                b[ev] = (p[ev] || []).map(function(path) {
                    return { fx: [sfx.make(path), sfx.make(path)], i: 0 };
                });
            });
        }
        sfx.bank = b;
    }
    onPackChanged: load()
    onVolumeChanged: {
        for (var i = 0; i < sfx.made.length; i++) if (sfx.made[i]) sfx.made[i].volume = sfx.volume;
    }

    // ev: key | space | enter | back | error | done | run
    // ch: the character typed — in a pitched pack the same letter is always
    // the same note, so a word has a tune and typing it again replays it
    function play(ev, ch) {
        if (sfx.muted) return;
        var list = sfx.bank[ev];
        if (!list || !list.length) return;
        var k = 0;
        if (list.length > 1) {
            if (sfx.info && sfx.info.pitched && ch) {
                var c = ch.toLowerCase().charCodeAt(0);
                k = (c >= 97 && c <= 122 ? c - 97 : c) % list.length;
            } else {
                do { k = Math.floor(Math.random() * list.length); } while (k === sfx.lastKey && list.length > 2);
                sfx.lastKey = k;
            }
        }
        var slot = list[k];
        var fx = slot.fx[slot.i];
        slot.i = (slot.i + 1) % slot.fx.length;
        if (fx) fx.play();
    }
}
