// The settings panel (F6). It never takes the keyboard from the page: arrows
// and Esc are routed here while it is open, and every other key still types,
// so you can change the entrance or the sound pack and try it on the spot.
// Each change is applied live and saved back through the hub.

import QtQuick

Item {
    id: pn
    property var w
    property bool shown: false
    property var values: ({})
    property int cur: 1
    property var packs: ["launcher"]
    signal changed(string key, var value)

    width: 380
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    x: shown ? parent.width - width : parent.width + 20
    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
    visible: x < parent.width

    readonly property var rows: [
        { head: "look" },
        { key: "entrance", label: "letters arrive", choices: ["launcher", "drop", "glitch", "stamp", "spin", "float", "random"],
          about: "launcher is the shell's own pop — try glitch and stamp" },
        { key: "exit", label: "letters leave", choices: ["launcher", "fall", "dust", "flick", "glitch"],
          about: "what backspace does to them" },
        { key: "colour", label: "colour", choices: ["theme", "flash", "rainbow", "accent"],
          about: "flash lands in the accent and cools down" },
        { key: "bounce", label: "bounce", range: [0, 10], about: "5 is exactly the launcher, 10 is rubber" },
        { key: "caret", label: "caret", choices: ["bar", "block", "underline"] },
        { key: "accent", label: "accent", choices: ["mauve", "blue", "peach", "teal", "red", "pink", "yellow", "green", "sapphire"],
          about: "taken from your live serpantinum theme" },
        { key: "size", label: "letter size", range: [12, 72], step: 2 },
        { key: "width", label: "line width", range: [20, 160], step: 4, about: "characters before words wrap" },
        { key: "direction", label: "text direction", choices: ["auto", "ltr", "rtl"],
          about: "WRITE and NOTES · auto: each paragraph follows its first letter, so Hebrew runs right to left" },
        { head: "feel" },
        { key: "sparks", label: "sparks", choices: ["on", "off"], about: "a little burst from every letter" },
        { key: "combo", label: "combo", choices: ["on", "off"], about: "keep typing without stopping and it climbs" },
        { key: "shake", label: "shake", choices: ["enter", "keys", "off"] },
        { key: "ripple", label: "ripple", choices: ["off", "on"], about: "each letter sends a wave back down the line" },
        { head: "sound" },
        { key: "soundpack", label: "sound pack", choices: pn.packs, about: "musicbox and chiptune play a note per letter" },
        { key: "volume", label: "volume", range: [0, 10], about: "on top of your shell's sfx volume" },
        { head: "code" },
        { key: "ghost", label: "ghost code", range: [0, 10], about: "how visible the code you're copying is" },
        { key: "strict", label: "strict", choices: ["off", "on"], about: "refuse wrong keys instead of typing them" },
        { head: "lyrics" },
        { key: "flow", label: "flow", choices: ["follow", "drive", "karaoke"],
          about: "follow: the song waits for you at every line · drive: plays while you type · karaoke: you race it" },
        { key: "lead", label: "singer's lead", range: [0, 3],
          about: "follow: lines the singer may get ahead before the song waits for you" },
        { key: "autoline", label: "auto next line", choices: ["on", "off"],
          about: "finish a line, keep typing, and you drop onto the next one" },
        { key: "grace", label: "grace", range: [3, 60], about: "drive: tenths of a second the song keeps going after your last key" },
        { head: "speed" },
        { key: "speed_time", label: "time", choices: ["15", "30", "60", "120", "infinite", "custom"],
          about: "infinite never stops and just shows your speed live" },
        { key: "speed_custom", label: "custom seconds", range: [10, 600], step: 5, about: "used when time is custom" },
        { key: "speed_text", label: "text", choices: ["words", "sentences", "hard", "page"],
          about: "hard throws in capitals, numbers and symbols · page is your WRITE page" },
        { head: "window" },
        { key: "window", label: "window", choices: ["window", "maximized", "fullscreen"] },
        { key: "keep", label: "keep the page", choices: ["on", "off"], about: "WRITE mode comes back as you left it" },
        { head: "reset" },
        { key: "__reset", label: "reset everything", action: true, about: "every setting back to its default — enter to do it" }
    ]
    property var defaults: ({})

    function open() { pn.shown = true; if (pn.rows[pn.cur].head) move(1); }
    function close() { pn.shown = false; }

    function move(d) {
        var i = pn.cur;
        do { i = (i + d + pn.rows.length) % pn.rows.length; } while (pn.rows[i].head);
        pn.cur = i;
        list.positionViewAtIndex(i, ListView.Contain);
        w.sfx.play("space");
    }

    function show(r) {
        if (r.action) return "↵";
        var v = pn.values[r.key];
        return v === undefined ? "—" : String(v);
    }

    function defaultOf(r) {
        var d = pn.defaults[r.key];
        if (d === undefined) return undefined;
        return r.range ? Number(d) : d;
    }
    function isDefault(r) {
        var d = defaultOf(r);
        return d === undefined || String(d) === String(pn.values[r.key]);
    }
    function setValue(key, v) {
        var copy = Object.assign({}, pn.values);
        copy[key] = v;
        pn.values = copy;
        pn.changed(key, v);
    }
    function resetOne() {
        var r = pn.rows[pn.cur];
        if (!r || r.head) return;
        if (r.action) { resetAll(); return; }
        if (isDefault(r)) return;
        var d = defaultOf(r);
        setValue(r.key, d);
        w.toast(r.label + " back to " + d);
    }
    function resetAll() {
        var n = 0;
        pn.rows.forEach(function(r) {
            if (!r.key || r.action || isDefault(r)) return;
            setValue(r.key, defaultOf(r));
            n++;
        });
        w.toast(n ? "everything back to defaults" : "already all defaults");
    }

    function cycle(d) {
        var r = pn.rows[pn.cur];
        if (!r || r.head) return;
        if (r.action) { resetAll(); return; }
        var v = pn.values[r.key], nv;
        if (r.choices) {
            var i = r.choices.indexOf(String(v));
            nv = r.choices[((i < 0 ? 0 : i) + d + r.choices.length) % r.choices.length];
        } else {
            var step = r.step || 1;
            nv = Math.max(r.range[0], Math.min(r.range[1], (Number(v) || r.range[0]) + d * step));
            if (nv === Number(v)) return;
        }
        var copy = Object.assign({}, pn.values);
        copy[r.key] = nv;
        pn.values = copy;
        pn.changed(r.key, nv);
    }

    // true when the key was the panel's
    function handle(e) {
        if (!pn.shown) return false;
        switch (e.key) {
        case Qt.Key_Up: move(-1); return true;
        case Qt.Key_Down: move(1); return true;
        case Qt.Key_Left: cycle(-1); return true;
        case Qt.Key_Right: cycle(1); return true;
        case Qt.Key_Delete: resetOne(); return true;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (pn.rows[pn.cur].action) { resetAll(); return true; }
            return false;
        case Qt.Key_Escape: case Qt.Key_F6: close(); return true;
        }
        return false;
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 14
        radius: w.radius * 1.6
        color: w.cPage
        border.width: 1
        border.color: Qt.alpha(w.cAccent, 0.35)

        Text {
            id: head
            x: 22; y: 18
            text: "settings"
            font.family: w.fontFamily
            font.pixelSize: 15
            font.letterSpacing: 2
            color: w.cAccent
        }
        // the total reset, where you can see it — two clicks, so a stray one
        // can't throw away everything you set up
        Rectangle {
            id: resetBtn
            property bool armed: false
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: head.verticalCenter
            width: resetLabel.implicitWidth + 22
            height: 26
            radius: 13
            color: armed ? Qt.alpha(w.cBad, 0.22) : (resetHover.hovered ? Qt.alpha(w.cAccent, 0.18) : "transparent")
            border.width: 1
            border.color: armed ? w.cBad : Qt.alpha(w.cAccent, 0.45)
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
                id: resetLabel
                anchors.centerIn: parent
                text: resetBtn.armed ? "sure? click again" : "↺ reset all"
                font.family: w.fontFamily
                font.pixelSize: 12
                color: resetBtn.armed ? w.cBad : w.cAccent
            }
            HoverHandler { id: resetHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (resetBtn.armed) { resetBtn.armed = false; disarm.stop(); pn.resetAll(); }
                    else { resetBtn.armed = true; disarm.restart(); }
                }
            }
            Timer { id: disarm; interval: 3000; onTriggered: resetBtn.armed = false }
        }

        ListView {
            id: list
            x: 10
            y: head.y + head.height + 12
            width: parent.width - 20
            height: parent.height - y - about.height - 34
            clip: true
            model: pn.rows
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                width: list.width
                height: modelData.head ? 34 : 32
                readonly property bool on: index === pn.cur
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    visible: !modelData.head
                    radius: w.radius
                    color: parent.on ? Qt.alpha(w.cAccent, 0.18) : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Text {
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: modelData.head ? 4 : 0
                    height: modelData.head ? implicitHeight : parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.head ? modelData.head.toUpperCase() : modelData.label
                    font.family: w.fontFamily
                    font.pixelSize: modelData.head ? 10 : 13
                    font.letterSpacing: modelData.head ? 3 : 0
                    color: modelData.head ? w.cSub : w.cText
                    opacity: modelData.head ? 0.6 : 1
                }
                Text {
                    visible: !modelData.head
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: (parent.on ? "‹  " : "") + pn.show(modelData) + (parent.on ? "  ›" : "")
                    font.family: w.fontFamily
                    font.pixelSize: 13
                    color: parent.on ? w.cAccent : w.cSub
                }
                // a changed setting gets a ↺ that puts it back
                Text {
                    visible: !modelData.head && !modelData.action && !pn.isDefault(modelData)
                    anchors.right: parent.right
                    anchors.rightMargin: -2
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "↺"
                    font.pixelSize: 11
                    color: w.cSub
                    opacity: 0.6
                    z: 2
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: { pn.cur = index; pn.resetOne(); }
                    }
                }
                // clicks change a value; the wheel is left alone so it scrolls
                // the list — it used to change whatever row was under it
                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 12
                    enabled: !modelData.head
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(m) { pn.cur = index; pn.cycle(m.button === Qt.RightButton ? -1 : 1); }
                }
            }
        }

        Text {
            id: about
            anchors.bottom: keys.top
            anchors.bottomMargin: 8
            x: 22
            width: parent.width - 44
            height: 34
            wrapMode: Text.WordWrap
            text: pn.rows[pn.cur] && pn.rows[pn.cur].about ? pn.rows[pn.cur].about : ""
            font.family: w.fontFamily
            font.pixelSize: 11
            color: w.cSub
        }
        Text {
            id: keys
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            text: "↑↓ pick  ·  ←→ or click change  ·  del reset  ·  f6 close"
            font.family: w.fontFamily
            font.pixelSize: 11
            color: w.cSub
            opacity: 0.6
        }
    }
}
