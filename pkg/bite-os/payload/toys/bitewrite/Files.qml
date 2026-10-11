// CODE: as many programs and pages as you like, side by side, each its own
// file with a name you chose, saved as you type.
//
// ~/.local/share/bite-os/bitewrite/code/<id>.txt holds one file's text and
// index.json holds the list (QML can write files but can't list a folder).
// The name carries the language: page.html is HTML, sketch.js is JavaScript,
// so renaming a file to another extension really does change what Ctrl+Enter
// does with it. Every text is read into memory at startup, because the little
// browser has to be able to open a page you haven't looked at this session.
//
// This is the list beside the page and the bookkeeping; the page itself is
// the same animated page as WRITE.

import QtQuick

Item {
    id: fs
    property var w
    property var page
    property string dir: ""
    property var files: []              // [{id, name, lang, updated, ghost}], newest first
    property string current: ""
    property bool ready: false
    property string armed: ""           // a file one click away from being deleted
    property string renaming: ""        // the file whose name is being edited
    property string pendingText: ""
    property var cache: ({})            // id → its text, always the newest
    property bool dirty: false
    readonly property bool active: w.mode === "code"

    x: 24
    y: page.y
    width: Math.max(0, page.x - 48)
    height: page.height
    visible: active && width >= 160

    readonly property var exts: ({ js: ".js", html: ".html", python: ".py", bash: ".sh" })
    readonly property var langOf: ({ ".js": "js", ".html": "html", ".htm": "html", ".py": "python", ".sh": "bash" })

    function path(id) { return fs.dir + "/" + id + ".txt"; }
    function saveIndex() { w.writeFile(fs.dir + "/index.json", JSON.stringify(fs.files)); }
    // by name, not by when it was touched: a list that reshuffles itself
    // while you type is a list you can’t keep your place in
    function sorted(list) {
        return list.slice().sort(function(a, b) {
            var x = a.name.toLowerCase(), y = b.name.toLowerCase();
            return x < y ? -1 : x > y ? 1 : 0;
        });
    }

    // F3 pressed while the folder is still being read waits its turn rather
    // than starting a second read of the same files
    property bool loading: false
    property var waiting: []
    function load(done) {
        if (fs.loading) { if (done) fs.waiting.push(done); return; }
        fs.loading = true;
        if (done) fs.waiting.push(done);
        w.readFile(fs.dir + "/index.json", function(raw) {
            var list = [];
            try { list = JSON.parse(raw) || []; } catch (e) { list = []; }
            list = list.filter(function(f) { return f && f.id && f.name; });
            fs.files = sorted(list);
            // every text, so a link to a page you never opened still resolves
            var left = fs.files.length;
            if (!left) { fs.done(); return; }
            fs.files.forEach(function(f) {
                w.readFile(path(f.id), function(txt) {
                    if (fs.cache[f.id] === undefined) fs.cache[f.id] = txt;
                    if (--left === 0) fs.done();
                });
            });
        });
    }

    function done() {
        fs.ready = true;
        fs.loading = false;
        var calls = fs.waiting;
        fs.waiting = [];
        calls.forEach(function(f) { f(); });
    }

    // ── names ───────────────────────────────────────────────────────────────

    function extOf(name) {
        var m = /(\.[a-z0-9]+)$/i.exec(String(name).trim());
        return m ? m[1].toLowerCase() : "";
    }
    function langFromName(name, fallback) {
        return fs.langOf[extOf(name)] || fallback || "js";
    }
    // A name you could type into a link: no spaces and nothing a file name
    // can't hold — but any alphabet is fine, and a / makes a folder, so
    // site/index.html is a file called index.html inside site.
    function withExt(name, lang) {
        var n = String(name).trim().replace(/\\/g, "/").replace(/\s+/g, "-")
                            .replace(/[<>:"'?*|]+/g, "-")
                            .replace(/\/+/g, "/").replace(/^[-./]+/, "").replace(/-+/g, "-");
        n = n.split("/").filter(function(part) { return part.length && part !== "."; }).join("/");
        if (!n || n.charAt(n.length - 1) === "/") n += "untitled";
        return fs.langOf[extOf(n)] ? n : n + (fs.exts[lang] || ".txt");
    }
    function folderOf(name) {
        var i = String(name).lastIndexOf("/");
        return i < 0 ? "" : name.slice(0, i);
    }
    function baseOf(name) {
        var i = String(name).lastIndexOf("/");
        return i < 0 ? name : name.slice(i + 1);
    }
    // the folder new files land in: whatever the open one is in
    readonly property string folder: fs.folderOf(fs.nameFor(fs.current))
    property string intoFolder: ""              // a folder just made, not yet used
    function slug(s) {
        return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "untitled";
    }
    function taken(name, notId) {
        for (var i = 0; i < fs.files.length; i++)
            if (fs.files[i].id !== notId && fs.files[i].name.toLowerCase() === name.toLowerCase()) return true;
        return false;
    }
    function freeName(name, notId) {
        var base = name, ext = extOf(name);
        if (ext) base = name.slice(0, name.length - ext.length);
        var n = name, i = 2;
        while (taken(n, notId)) n = base + "-" + (i++) + ext;
        return n;
    }

    // ── the files ───────────────────────────────────────────────────────────

    function create(name, lang, text, ghost) {
        flush();
        var id = String(Date.now());
        var into = fs.intoFolder || fs.folder;
        var want = String(name || "untitled");
        if (into && want.indexOf("/") < 0) want = into + "/" + want;
        fs.intoFolder = "";
        var nm = freeName(withExt(want, lang), "");
        fs.files = sorted([{ id: id, name: nm, lang: lang, updated: Date.now(), ghost: ghost || "" }].concat(fs.files));
        fs.current = id;
        fs.cache[id] = text || "";
        w.writeFile(path(id), text || "");
        saveIndex();
        return id;
    }

    function open(id, done) {
        flush();
        fs.current = id;
        done(fs.cache[id] !== undefined ? fs.cache[id] : "");
    }

    function changed(text) {
        fs.pendingText = text;
        fs.dirty = true;
        saveTimer.restart();
    }
    function flush() {
        if (!fs.dirty || !fs.current) return;
        fs.dirty = false;
        saveTimer.stop();
        fs.cache[fs.current] = fs.pendingText;
        w.writeFile(path(fs.current), fs.pendingText);
        touch(fs.current);
    }
    Timer { id: saveTimer; interval: 500; onTriggered: fs.flush() }

    function touch(id) {
        var list = fs.files.slice();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id) list[i] = merge(list[i], { updated: Date.now() });
        fs.files = sorted(list);
        saveIndex();
    }
    function merge(a, b) {
        var out = {};
        for (var k in a) out[k] = a[k];
        for (var j in b) out[j] = b[j];
        return out;
    }
    function set(id, fields) {
        var list = fs.files.slice();
        for (var i = 0; i < list.length; i++) if (list[i].id === id) list[i] = merge(list[i], fields);
        fs.files = sorted(list);
        saveIndex();
    }

    // a new name can change the language too: page.js is a program, page.html
    // is a page, and Ctrl+Enter does the right thing with either
    function rename(id, name) {
        var e = entry(id);
        if (!e) return "";
        var nm = freeName(withExt(name, e.lang), id);
        fs.set(id, { name: nm, lang: langFromName(nm, e.lang), updated: Date.now() });
        return nm;
    }

    function remove(id) {
        if (id === fs.current) fs.dirty = false;
        delete fs.cache[id];
        delete fs.ranCache[id];
        fs.files = fs.files.filter(function(f) { return f.id !== id; });
        saveIndex();
    }

    // What this file looked like the last time you ran it — kept beside it as
    // <id>.ran.txt, so "what did I change since it worked?" survives a restart.
    property var ranCache: ({})
    function snapshot(id, text) {
        if (!id) return;
        fs.ranCache[id] = text;
        w.writeFile(fs.dir + "/" + id + ".ran.txt", text);
        fs.set(id, { ran: Date.now() });
    }
    function ranAt(id) { var e = entry(id); return e && e.ran ? e.ran : 0; }
    function ranOf(id, done) {
        if (fs.ranCache[id] !== undefined) { done(fs.ranCache[id]); return; }
        w.readFile(fs.dir + "/" + id + ".ran.txt", function(t) {
            if (fs.ranCache[id] === undefined) fs.ranCache[id] = t;
            done(fs.ranCache[id]);
        });
    }

    function entry(id) {
        for (var i = 0; i < fs.files.length; i++) if (fs.files[i].id === id) return fs.files[i];
        return null;
    }
    function nameFor(id) { var e = entry(id); return e ? e.name : ""; }
    function langFor(id) { var e = entry(id); return e ? e.lang : "js"; }
    function ghostFor(id) { var e = entry(id); return e ? (e.ghost || "") : ""; }
    function textOf(id) {
        // the file being edited is newer on the page than on the disk
        if (id === fs.current && fs.dirty) return fs.pendingText;
        return fs.cache[id] !== undefined ? fs.cache[id] : "";
    }

    function neighbor(d) {
        for (var i = 0; i < fs.files.length; i++)
            if (fs.files[i].id === fs.current) {
                var j = i + d;
                return j >= 0 && j < fs.files.length ? fs.files[j].id : "";
            }
        return fs.files.length ? fs.files[0].id : "";
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
    property int tick: 0
    Timer { interval: 30000; repeat: true; running: fs.active; onTriggered: fs.tick++ }

    // one row per folder and one per file, folders first, so the list can be
    // a flat ListView and still look like a tree
    property var collapsed: ({})
    function fold(name) {
        var c = fs.collapsed;
        c[name] = !c[name];
        fs.collapsed = Object.assign({}, c);
    }
    readonly property var rows: {
        var out = [], seen = {}, i;
        var folders = [];
        for (i = 0; i < fs.files.length; i++) {
            var f = fs.folderOf(fs.files[i].name);
            if (f && !seen[f]) { seen[f] = true; folders.push(f); }
        }
        folders.sort();
        for (i = 0; i < folders.length; i++) {
            var n = 0;
            for (var k = 0; k < fs.files.length; k++)
                if (fs.folderOf(fs.files[k].name) === folders[i]) n++;
            out.push({ kind: "folder", name: folders[i], count: n, id: "folder:" + folders[i] });
            if (fs.collapsed[folders[i]]) continue;
            for (var j = 0; j < fs.files.length; j++)
                if (fs.folderOf(fs.files[j].name) === folders[i]) out.push(rowFor(fs.files[j]));
        }
        for (i = 0; i < fs.files.length; i++)
            if (!fs.folderOf(fs.files[i].name)) out.push(rowFor(fs.files[i]));
        return out;
    }
    function rowFor(f) {
        return { kind: "file", id: f.id, name: f.name, base: fs.baseOf(f.name),
                 lang: f.lang, updated: f.updated, deep: fs.folderOf(f.name) !== "" };
    }
    function inFolder(name) {
        return fs.files.filter(function(f) { return fs.folderOf(f.name) === name; });
    }

    function arm(id) { fs.armed = id; disarm.restart(); }
    Timer { id: disarm; interval: 2500; onTriggered: fs.armed = "" }

    // the rename box lives inside a delegate, so it hands itself over here
    property var renameField: null
    function startRename(id) { fs.renaming = id; }
    function endRename(accept) {
        var id = fs.renaming, typed = fs.renameField ? fs.renameField.text : "";
        fs.renaming = "";
        if (!id) return;
        if (accept && typed.trim().length) {
            var nm = fs.rename(id, typed);
            if (nm) w.toast("renamed → " + nm + "   ·   " + w.langNames[fs.langFor(id)]);
        }
        w.focusPage();
    }

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
        text: "FILES"
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
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.newCodeFile() }
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
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: fs.startFolder() }
    }

    // a new folder is a name typed at the top of the list; the file that goes
    // in it is the next one you make
    property string makingFolder: ""
    property var folderField: null
    function startFolder() { fs.makingFolder = "new"; }
    function endFolder(accept) {
        var typed = fs.folderField ? fs.folderField.text : "";
        fs.makingFolder = "";
        if (!accept || !typed.trim().length) { w.focusPage(); return; }
        fs.intoFolder = fs.withExt(typed.trim() + "/keep", "js").replace(/\/keep\.js$/, "");
        w.newCodeFile();
    }

    Loader {
        id: folderBox
        active: fs.makingFolder !== ""
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
                text: ""
                font.family: w.fontFamily
                font.pixelSize: 13
                color: w.cText
                selectionColor: Qt.alpha(w.cAccent, 0.4)
                Component.onCompleted: { fs.folderField = folderField; forceActiveFocus(); }
                Component.onDestruction: if (fs.folderField === folderField) fs.folderField = null
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) fs.endFolder(true);
                    else if (e.key === Qt.Key_Escape) fs.endFolder(false);
                    else return;
                    e.accepted = true;
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                visible: !fs.folderField || !fs.folderField.text.length
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
        model: fs.rows
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: row.modelData.kind === "folder" ? 28 : 48
            readonly property bool isFolder: modelData.kind === "folder"
            readonly property bool on: !isFolder && modelData.id === fs.current
            readonly property bool armedHere: fs.armed === modelData.id
            readonly property bool editing: fs.renaming === modelData.id
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
                    if (row.isFolder) fs.fold(row.modelData.name);
                    else if (!row.on) w.openCodeFile(row.modelData.id);
                }
                onDoubleClicked: if (!row.isFolder) fs.startRename(row.modelData.id)
            }

            // ── a folder ────────────────────────────────────────────────────
            Text {
                visible: row.isFolder
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: (fs.collapsed[row.modelData.name] ? "▸  " : "▾  ") + row.modelData.name
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

            // ── a file ──────────────────────────────────────────────────────
            Text {
                visible: !row.isFolder && !row.editing
                x: row.modelData.deep ? 26 : 12
                y: 7
                width: parent.width - x - 36
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: row.isFolder ? "" : row.modelData.base
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
                        id: renameField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        text: row.modelData.name
                        font.family: w.fontFamily
                        font.pixelSize: 13
                        color: w.cText
                        selectionColor: Qt.alpha(w.cAccent, 0.4)
                        Component.onCompleted: { fs.renameField = renameField; forceActiveFocus(); selectAll(); }
                        Component.onDestruction: if (fs.renameField === renameField) fs.renameField = null
                        Keys.onPressed: function(e) {
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) fs.endRename(true);
                            else if (e.key === Qt.Key_Escape) fs.endRename(false);
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
                text: row.isFolder ? "" : row.modelData.lang + "   ·   " + (fs.tick, fs.ago(row.modelData.updated))
                font.family: w.fontFamily
                font.pixelSize: 10
                color: w.cSub
                opacity: 0.7
            }

            // ── throwing it away ────────────────────────────────────────────
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
                        if (!row.armedHere) { fs.arm(row.modelData.id); return; }
                        fs.armed = "";
                        if (row.isFolder) w.deleteCodeFolder(row.modelData.name);
                        else w.deleteCodeFile(row.modelData.id);
                    }
                }
            }
        }
    }
}
