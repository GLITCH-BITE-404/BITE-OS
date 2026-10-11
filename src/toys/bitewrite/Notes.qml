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
    property var notes: []              // [{id, title, folder, updated}], newest first
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

    // where a new note lands: the folder of the one you're reading, or the
    // folder you just made
    readonly property string folder: nt.folderFor(nt.current)
    property string intoFolder: ""
    function folderFor(id) { var n = entry(id); return n && n.folder ? n.folder : ""; }
    function entry(id) {
        for (var i = 0; i < nt.notes.length; i++) if (nt.notes[i].id === id) return nt.notes[i];
        return null;
    }
    function cleanFolder(name) {
        return String(name || "").replace(/\\/g, "/").replace(/\s+/g, "-")
               .replace(/[<>:"'?*|]+/g, "-").replace(/\/+/g, "/")
               .split("/").filter(function(p) { return p.length && p !== "."; }).join("/");
    }
    function move(id, folder) {
        var f = cleanFolder(folder);
        var list = nt.notes.slice();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id) list[i] = { id: id, title: list[i].title, folder: f, updated: Date.now() };
        nt.notes = sorted(list);
        saveIndex();
        return f;
    }

    function create() {
        flush();
        var id = String(Date.now());
        var into = nt.intoFolder || nt.folder;
        nt.intoFolder = "";
        nt.notes = [{ id: id, title: "untitled", folder: into, updated: Date.now() }].concat(nt.notes);
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

    // every note's text, for taking the whole lot out of the toy at once
    function loadAll(done) {
        flush();
        var left = 0;
        nt.notes.forEach(function(n) { if (nt.cache[n.id] === undefined) left++; });
        if (!left) { done(); return; }
        nt.notes.forEach(function(n) {
            if (nt.cache[n.id] !== undefined) return;
            w.readFile(path(n.id), function(txt) {
                if (nt.cache[n.id] === undefined) nt.cache[n.id] = txt;
                if (--left === 0) done();
            });
        });
    }
    function textOf(id) {
        if (id === nt.current && nt.dirty) return nt.pendingText;
        return nt.cache[id] !== undefined ? nt.cache[id] : "";
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
            if (list[i].id === nt.current)
                list[i] = { id: nt.current, title: title, folder: list[i].folder || "", updated: Date.now() };
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

    // one row per folder and one per note, so a flat list can look like a tree
    property var collapsed: ({})
    function fold(name) {
        var c = nt.collapsed;
        c[name] = !c[name];
        nt.collapsed = Object.assign({}, c);
    }
    function inFolder(name) {
        return nt.notes.filter(function(n) { return (n.folder || "") === name; });
    }
    readonly property var rows: {
        var out = [], seen = {}, folders = [], i;
        for (i = 0; i < nt.notes.length; i++) {
            var f = nt.notes[i].folder || "";
            if (f && !seen[f]) { seen[f] = true; folders.push(f); }
        }
        folders.sort();
        for (i = 0; i < folders.length; i++) {
            var inside = nt.inFolder(folders[i]);
            out.push({ kind: "folder", name: folders[i], count: inside.length, id: "folder:" + folders[i] });
            if (nt.collapsed[folders[i]]) continue;
            for (var j = 0; j < inside.length; j++)
                out.push({ kind: "note", id: inside[j].id, title: inside[j].title,
                           updated: inside[j].updated, deep: true });
        }
        var loose = nt.inFolder("");
        for (i = 0; i < loose.length; i++)
            out.push({ kind: "note", id: loose[i].id, title: loose[i].title,
                       updated: loose[i].updated, deep: false });
        return out;
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

    Rectangle {
        id: folderBtn
        anchors.right: newBtn.left
        anchors.rightMargin: 8
        anchors.verticalCenter: head.verticalCenter
        width: folderLabel.implicitWidth + 16
        height: 24
        radius: 12
        color: folderHover.hovered ? Qt.alpha(w.cText, 0.1) : "transparent"
        border.width: 1
        border.color: Qt.alpha(w.cEdge, 0.9)
        Text {
            id: folderLabel
            anchors.centerIn: parent
            text: "+ folder"
            font.family: w.fontFamily
            font.pixelSize: 12
            color: w.cSub
        }
        HoverHandler { id: folderHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nt.startFolder() }
    }

    // a new folder is a name typed at the top of the list; the note that goes
    // in it is the next one you make
    property string makingFolder: ""
    property var folderField: null
    property string moving: ""                  // the note whose folder is being typed
    property var moveField: null
    function startFolder() { nt.makingFolder = "new"; }
    function endFolder(accept) {
        var typed = nt.folderField ? nt.folderField.text : "";
        nt.makingFolder = "";
        if (!accept || !typed.trim().length) { w.focusPage(); return; }
        nt.intoFolder = nt.cleanFolder(typed);
        w.newNote();
    }
    function startMove(id) { nt.moving = id; }
    function endMove(accept) {
        var id = nt.moving, typed = nt.moveField ? nt.moveField.text : "";
        nt.moving = "";
        if (!id) return;
        if (accept) {
            var f = nt.move(id, typed);
            w.toast(f ? "moved into " + f + "/" : "moved out of its folder");
        }
        w.focusPage();
    }

    Loader {
        id: folderBox
        active: nt.makingFolder !== ""
        x: 8
        y: head.y + head.height + 12
        width: parent.width - 16
        height: 28
        sourceComponent: Rectangle {
            radius: w.radius
            color: w.cBase
            border.width: 1
            border.color: Qt.alpha(w.cAccent, 0.5)
            TextInput {
                id: folderField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: w.fontFamily
                font.pixelSize: 13
                color: w.cText
                selectionColor: Qt.alpha(w.cAccent, 0.4)
                Component.onCompleted: { nt.folderField = folderField; forceActiveFocus(); }
                Component.onDestruction: if (nt.folderField === folderField) nt.folderField = null
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) nt.endFolder(true);
                    else if (e.key === Qt.Key_Escape) nt.endFolder(false);
                    else return;
                    e.accepted = true;
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                visible: !nt.folderField || !nt.folderField.text.length
                text: "a folder name…"
                font.family: w.fontFamily
                font.pixelSize: 13
                color: w.cSub
                opacity: 0.5
            }
        }
    }

    ListView {
        id: list
        x: 8
        y: (folderBox.active ? folderBox.y + folderBox.height + 6 : head.y + head.height + 14)
        width: parent.width - 16
        height: parent.height - y - 10
        clip: true
        model: nt.rows
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: row.modelData.kind === "folder" ? 28 : 48
            readonly property bool isFolder: modelData.kind === "folder"
            readonly property bool on: !isFolder && modelData.id === nt.current
            readonly property bool armedHere: nt.armed === modelData.id
            readonly property bool editing: nt.moving === modelData.id
            HoverHandler { id: rowHover }

            Rectangle {
                anchors.fill: parent
                radius: w.radius
                color: row.on ? Qt.alpha(w.cAccent, 0.2)
                     : (rowHover.hovered ? Qt.alpha(w.cText, row.isFolder ? 0.04 : 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !row.editing
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.isFolder) nt.fold(row.modelData.name);
                    else if (!row.on) w.openNote(row.modelData.id);
                }
                onDoubleClicked: if (!row.isFolder) nt.startMove(row.modelData.id)
            }

            Text {
                visible: row.isFolder
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: (nt.collapsed[row.modelData.name] ? "▸  " : "▾  ") + row.modelData.name
                font.family: w.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 1
                color: w.cSub
            }
            Text {
                visible: row.isFolder && !row.armedHere
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.isFolder ? String(row.modelData.count) : ""
                font.family: w.fontFamily
                font.pixelSize: 11
                color: w.cSub
                opacity: 0.6
            }

            // no alignment set on purpose: Qt lines a Hebrew title up on the right
            Text {
                visible: !row.isFolder && !row.editing
                x: row.modelData.deep ? 26 : 12
                y: 7
                width: parent.width - x - 36
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.isFolder ? "" : row.modelData.title
                font.family: w.fontFamily
                font.pixelSize: 13
                color: row.on ? w.cText : Qt.alpha(w.cText, 0.8)
            }
            Loader {
                active: row.editing
                x: row.modelData.deep ? 24 : 10
                y: 4
                width: parent.width - x - 36
                height: 24
                sourceComponent: Rectangle {
                    radius: w.radius
                    color: w.cBase
                    border.width: 1
                    border.color: Qt.alpha(w.cAccent, 0.5)
                    TextInput {
                        id: moveField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        text: nt.folderFor(row.modelData.id)
                        font.family: w.fontFamily
                        font.pixelSize: 13
                        color: w.cText
                        selectionColor: Qt.alpha(w.cAccent, 0.4)
                        Component.onCompleted: { nt.moveField = moveField; forceActiveFocus(); selectAll(); }
                        Component.onDestruction: if (nt.moveField === moveField) nt.moveField = null
                        Keys.onPressed: function(e) {
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) nt.endMove(true);
                            else if (e.key === Qt.Key_Escape) nt.endMove(false);
                            else return;
                            e.accepted = true;
                        }
                    }
                }
            }
            Text {
                visible: !row.isFolder
                x: row.modelData.deep ? 26 : 12
                y: 27
                text: row.isFolder ? "" : (nt.tick, nt.ago(row.modelData.updated))
                font.family: w.fontFamily
                font.pixelSize: 10
                color: w.cSub
                opacity: 0.7
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.editing && (rowHover.hovered || row.armedHere)
                text: row.armedHere ? (row.isFolder ? "delete " + row.modelData.count + "?" : "sure?") : "✕"
                font.family: w.fontFamily
                font.pixelSize: row.armedHere ? 11 : 12
                color: row.armedHere ? w.cBad : w.cSub
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!row.armedHere) { nt.arm(row.modelData.id); return; }
                        nt.armed = "";
                        if (row.isFolder) w.deleteNotesFolder(row.modelData.name);
                        else w.deleteNote(row.modelData.id);
                    }
                }
            }
        }
    }
}
