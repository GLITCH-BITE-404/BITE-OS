// NOTES: as many notes as you like, each its own file, saved as you type.
//
// ~/.local/share/bite-os/bitewrite/notes/<id>.txt holds a note, and
// index.json holds the list (QML can write files but can't list a folder).
// A note's title is its first line. The page itself is the same animated
// page as WRITE — this is the list beside it and the bookkeeping.

import QtQuick

Item {
    id: nt
    property var w
    property var page
    property string dir: ""
    property var notes: []              // [{id, title, updated}], newest first
    property string current: ""
    property bool ready: false
    property string armed: ""           // a note one click away from being deleted
    property string pendingText: ""
    // the latest text of every note this session has touched: switching
    // reads from here, because a note written a moment ago may still be on
    // its way to the disk, and reading the file then gave back the old text
    property var cache: ({})
    property bool dirty: false
    readonly property bool active: w.mode === "notes"

    x: 24
    y: page.y
    width: Math.max(0, page.x - 48)
    height: page.height
    visible: active && width >= 160

    function path(id) { return nt.dir + "/" + id + ".txt"; }

    function load(done) {
        w.readFile(nt.dir + "/index.json", function(raw) {
            var list = [];
            try { list = JSON.parse(raw) || []; } catch (e) { list = []; }
            nt.notes = sorted(list.filter(function(n) { return n && n.id; }));
            nt.ready = true;
            if (done) done();
        });
    }
    function saveIndex() { w.writeFile(nt.dir + "/index.json", JSON.stringify(nt.notes)); }
    function sorted(list) { return list.slice().sort(function(a, b) { return b.updated - a.updated; }); }

    function titleOf(text) {
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim();
            if (t) return t.length > 48 ? t.slice(0, 48) + "…" : t;
        }
        return "untitled";
    }

    function create() {
        flush();
        var id = String(Date.now());
        nt.notes = [{ id: id, title: "untitled", updated: Date.now() }].concat(nt.notes);
        nt.current = id;
        saveIndex();
        nt.cache[id] = "";
        w.writeFile(path(id), "");
        return id;
    }

    function open(id, done) {
        flush();
        nt.current = id;
        if (nt.cache[id] !== undefined) { done(nt.cache[id]); return; }
        w.readFile(path(id), function(txt) {
            if (nt.cache[id] === undefined) nt.cache[id] = txt;
            done(nt.cache[id]);
        });
    }

    // the page changed: remember it, write it a moment later
    function changed(text) {
        nt.pendingText = text;
        nt.dirty = true;
        saveTimer.restart();
    }
    function flush() {
        if (!nt.dirty || !nt.current) return;
        nt.dirty = false;
        saveTimer.stop();
        nt.cache[nt.current] = nt.pendingText;
        w.writeFile(path(nt.current), nt.pendingText);
        var list = nt.notes.slice(), title = titleOf(nt.pendingText);
        for (var i = 0; i < list.length; i++)
            if (list[i].id === nt.current) list[i] = { id: nt.current, title: title, updated: Date.now() };
        nt.notes = sorted(list);
        saveIndex();
    }
    Timer { id: saveTimer; interval: 500; onTriggered: nt.flush() }

    function remove(id) {
        if (id === nt.current) nt.dirty = false;
        delete nt.cache[id];
        nt.notes = nt.notes.filter(function(n) { return n.id !== id; });
        saveIndex();
    }

    // the note above or below the current one in the list
    function neighbor(d) {
        for (var i = 0; i < nt.notes.length; i++)
            if (nt.notes[i].id === nt.current) {
                var j = i + d;
                return j >= 0 && j < nt.notes.length ? nt.notes[j].id : "";
            }
        return nt.notes.length ? nt.notes[0].id : "";
    }

    function titleFor(id) {
        for (var i = 0; i < nt.notes.length; i++) if (nt.notes[i].id === id) return nt.notes[i].title;
        return "";
    }

    function ago(ms) {
        var s = (Date.now() - ms) / 1000;
        if (s < 45) return "now";
        if (s < 3600) return Math.round(s / 60) + "m";
        if (s < 86400) return Math.round(s / 3600) + "h";
        if (s < 172800) return "yesterday";
        var d = new Date(ms);
        return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
    }
    // refreshes the "5m ago" labels now and then
    property int tick: 0
    Timer { interval: 30000; repeat: true; running: nt.active; onTriggered: nt.tick++ }

    function arm(id) {
        nt.armed = id;
        disarm.restart();
    }
    Timer { id: disarm; interval: 2500; onTriggered: nt.armed = "" }

    // ── the list ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: w.radius * 1.6
        color: Qt.alpha(w.cPage, 0.55)
        border.width: 1
        border.color: Qt.alpha(w.cEdge, 0.5)
    }

    Text {
        id: head
        x: 18; y: 16
        text: "NOTES"
        font.family: w.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 3
        color: w.cSub
    }

    Rectangle {
        id: newBtn
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: head.verticalCenter
        width: newLabel.implicitWidth + 18
        height: 24
        radius: 12
        color: newHover.hovered ? Qt.alpha(w.cAccent, 0.2) : "transparent"
        border.width: 1
        border.color: Qt.alpha(w.cAccent, 0.45)
        Text {
            id: newLabel
            anchors.centerIn: parent
            text: "+ new"
            font.family: w.fontFamily
            font.pixelSize: 12
            color: w.cAccent
        }
        HoverHandler { id: newHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.newNote() }
    }

    ListView {
        id: list
        x: 8
        y: head.y + head.height + 14
        width: parent.width - 16
        height: parent.height - y - 10
        clip: true
        model: nt.notes
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: row
            width: list.width
            height: 48
            readonly property bool on: modelData.id === nt.current
            readonly property bool armedHere: nt.armed === modelData.id
            HoverHandler { id: rowHover }

            Rectangle {
                anchors.fill: parent
                radius: w.radius
                color: row.on ? Qt.alpha(w.cAccent, 0.2) : (rowHover.hovered ? Qt.alpha(w.cText, 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!row.on) w.openNote(modelData.id)
            }
            // no alignment set on purpose: Qt lines a Hebrew title up on the right
            Text {
                x: 12; y: 7
                width: parent.width - 48
                elide: Text.ElideRight
                text: modelData.title
                font.family: w.fontFamily
                font.pixelSize: 13
                color: row.on ? w.cText : Qt.alpha(w.cText, 0.8)
            }
            Text {
                x: 12; y: 27
                text: (nt.tick, nt.ago(modelData.updated))
                font.family: w.fontFamily
                font.pixelSize: 10
                color: w.cSub
                opacity: 0.7
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: rowHover.hovered || row.armedHere
                text: row.armedHere ? "sure?" : "✕"
                font.family: w.fontFamily
                font.pixelSize: row.armedHere ? 11 : 12
                color: row.armedHere ? w.cBad : w.cSub
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.armedHere) { nt.armed = ""; w.deleteNote(modelData.id); }
                        else nt.arm(modelData.id);
                    }
                }
            }
        }
    }
}
