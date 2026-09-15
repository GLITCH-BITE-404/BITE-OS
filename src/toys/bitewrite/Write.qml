// bitewrite — the launcher's search box, turned into a whole page.
//
// Four modes behind one page:
//   WRITE   free writing, kept between sessions
//   CODE    write a program (or type one over its ghost); Ctrl+Enter runs
//           whatever you wrote — broken code doesn't run, valid code does
//   LYRICS  a song's lyrics as the ghost; your typing drives the song
//   SPEED   a typing test with your speed live at the bottom
//
// A hidden TextEdit owns the text (typing, undo, paste, the keyboard caret
// all come free) and every character is its own Glyph on a monospace grid,
// fed by a prefix/suffix diff so only changed letters are born or die. What
// you type is held against the ghost by align.js, line by line and word by
// word. Animation numbers for the default style are lifted from serpantinum's
// reusables/Input.qml, so it FEELS like the launcher rather than resembling it.

import QtQuick
import QtQuick.Window
import QtQuick.Particles
import "align.js" as Align

Window {
    id: win
    width: 1100
    height: 740
    visible: true
    title: "bitewrite"
    color: win.cBase

    // ── settings (opts.json, written by engine.py --prep) ───────────────────
    property var pal: ({})
    property color cBase: "#221a0f"
    property color cPage: "#312618"
    property color cEdge: "#423423"
    property color cText: "#eddcd2"
    property color cSub: "#a89386"
    property color cAccent: "#b5838d"
    property color cBad: "#e76f51"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property real radius: 10
    property int userPx: 28
    property int maxCols: 60
    property real overshoot: 3.2
    property string entrance: "launcher"
    property string exit: "launcher"
    property string colour: "theme"
    property string caretStyle: "bar"
    property bool sparksOn: true
    property bool comboOn: true
    property string shake: "enter"
    property bool ripple: false
    property int ghostLevel: 3
    property bool strict: false
    property string flow: "follow"
    property int lead: 0
    property bool autoline: true
    property int grace: 15
    property string speedTime: "60"
    property int speedCustom: 90
    property string speedText: "words"
    property bool keep: true
    property real shellVolume: 1.0
    property string draftPath: ""
    property string bestsPath: ""
    property string docsDir: ""
    property string homeDir: ""
    property var snippetList: []
    property bool ready: false
    property var sfx: sfxObj

    // ── mode ────────────────────────────────────────────────────────────────
    property string mode: "write"
    property string target: ""         // the ghost, in CODE, LYRICS and SPEED
    property var ghostLines: []
    property var ghostView: []         // per row: the part of the ghost still to type
    property string writeText: ""      // WRITE's page while another mode is up
    property string pieceName: ""
    property bool ghostHidden: false
    property bool complete: false
    property bool alignComplete: false
    property int wrong: 0
    property int typedMax: 0
    property var compileState: null
    readonly property bool ghosted: win.mode !== "write" && win.target.length > 0
    // code never wraps (a wrapped line of code is a different line of code),
    // and neither does anything with a ghost, so typing sits on top of it
    readonly property bool nowrap: win.ghosted || win.mode === "code"
    // LYRICS and SPEED: every key fills the next slot of the ghost and the
    // line never moves (see align.js slots())
    readonly property bool slotMode: win.ghosted && (win.mode === "lyrics" || win.mode === "speed")

    // ── grid ────────────────────────────────────────────────────────────────
    readonly property int longest: {
        var m = 0;
        for (var i = 0; i < win.ghostLines.length; i++) m = Math.max(m, win.ghostLines[i].length);
        return m;
    }
    // with a ghost, the letters shrink to fit its longest line
    readonly property int fitPx: win.ghosted ? Math.floor((win.width - 150) / (win.longest + 3) / 0.62) : 999
    readonly property int fontPx: Math.max(12, Math.min(win.userPx, win.fitPx))
    // advanceWidth, not width: width is the ink of "0" alone, a few pixels
    // narrower than the step the font actually takes
    readonly property real charW: metrics.advanceWidth
    readonly property real slot: metrics.advanceWidth + 1   // +1 is the launcher's charSpacing
    readonly property real lineH: Math.round(win.fontPx * 1.7)
    readonly property real padX: Math.round(win.fontPx * 1.3)
    readonly property real padY: Math.round(win.fontPx * 0.9)
    readonly property int fitCols: Math.max(8, Math.floor((win.width - 96 - 2 * win.padX) / win.slot))
    readonly property int cols: win.ghosted ? Math.max(win.longest + 1, 8)
                              : (win.mode === "code" ? win.fitCols : Math.min(win.maxCols, win.fitCols))
    function fitColsAt(px) { return Math.floor((win.width - 150) / (px * 0.62)) - 3; }

    property var units: []
    property var pc: []
    property var pr: []
    property var badArr: []
    property int endCol: 0
    property int endRow: 0
    property int caretCol: 0
    property int caretRow: 0
    property var selSegs: []
    property bool quiet: false

    readonly property int firstRow: Math.floor(flick.contentY / win.lineH)
    readonly property int lastRow: Math.ceil((flick.contentY + flick.height) / win.lineH)
    function near(row) { return row >= win.firstRow - 2 && row <= win.lastRow + 2; }

    readonly property string noiseChars: "!<>-_\\/[]{}—=+*^?#01░▒"
    function noise(p) { return win.noiseChars[Math.floor(Math.random() * win.noiseChars.length)]; }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    function randomStyle() {
        var s = ["launcher", "drop", "glitch", "stamp", "spin", "float"];
        return s[Math.floor(Math.random() * s.length)];
    }

    TextMetrics { id: metrics; font.family: win.fontFamily; font.pixelSize: win.fontPx; text: "0" }
    ListModel { id: charModel }
    Sfx { id: sfxObj }
    property var ghostComp: Qt.createComponent("Ghost.qml")

    // ── files ───────────────────────────────────────────────────────────────
    // "file://" + a bare name makes the name a HOST, so relative paths go
    // through resolvedUrl (the run directory); absolute ones are encoded,
    // because the Documents folder is often not ASCII
    function fileUrl(path) {
        return path.charAt(0) === "/" ? "file://" + encodeURI(path) : Qt.resolvedUrl(path);
    }
    function readFile(path, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() { if (x.readyState === XMLHttpRequest.DONE) done(x.responseText || ""); };
        x.open("GET", fileUrl(path));
        x.send();
    }
    function writeFile(path, text, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() { if (x.readyState === XMLHttpRequest.DONE && done) done(); };
        x.open("PUT", fileUrl(path));
        x.send(text);
    }

    // ── the engine ──────────────────────────────────────────────────────────
    // One request at a time: request.json is a single slot, so a second write
    // before the engine read the first would silently replace it.
    property int seq: 0
    property var queue: []
    property var waiting: null
    function ask(obj, cb) {
        win.queue.push({ obj: obj, cb: cb });
        if (!win.waiting) sendNext();
    }
    function sendNext() {
        if (!win.queue.length) { win.waiting = null; return; }
        var q = win.queue.shift();
        win.seq++;
        q.obj.seq = win.seq;
        win.waiting = { seq: win.seq, cb: q.cb, sent: Date.now() };
        writeFile("request.json", JSON.stringify(q.obj));
        answerPoll.start();
    }
    Timer {
        id: answerPoll
        interval: 70
        repeat: true
        onTriggered: {
            if (!win.waiting) { stop(); return; }
            if (Date.now() - win.waiting.sent > 25000) {           // engine gone: don't wedge
                var dead = win.waiting; win.waiting = null;
                if (dead.cb) dead.cb({ ok: false, error: "the engine didn't answer" });
                sendNext(); return;
            }
            readFile("status.json", function(raw) {
                var r; try { r = JSON.parse(raw); } catch (e) { return; }
                if (!win.waiting || r.seq !== win.waiting.seq) return;
                var w0 = win.waiting; win.waiting = null;
                if (w0.cb) w0.cb(r);
                sendNext();
            });
        }
    }

    // settings changed in the panel are saved in one batch after a pause
    property var dirty: ({})
    Timer {
        id: saveSettings
        interval: 600
        onTriggered: {
            var pairs = win.dirty; win.dirty = {};
            if (Object.keys(pairs).length) ask({ action: "set", pairs: pairs }, null);
        }
    }
    // a setting changed from outside the panel (SPEED's chips, Tab)
    function setSetting(key, value) {
        var v = Object.assign({}, panel.values); v[key] = value; panel.values = v;
        apply(key, value, false);
        var d = win.dirty; d[key] = String(value); win.dirty = d;
        saveSettings.restart();
    }

    // ── start ───────────────────────────────────────────────────────────────
    Component.onCompleted: {
        readFile("opts.json", function(raw) {
            var o = {};
            try { o = JSON.parse(raw); } catch (e) { console.warn("bitewrite: opts.json unreadable, using defaults"); }
            win.pal = o.pal || {};
            var P = win.pal;
            if (P.base) win.cBase = P.base;
            if (P.surface0) win.cPage = P.surface0;
            if (P.surface1) win.cEdge = P.surface1;
            if (P.text) win.cText = P.text;
            if (P.subtext0) win.cSub = P.subtext0;
            if (P.red) win.cBad = P.red;
            if (o.font) win.fontFamily = o.font;
            if (o.radius !== undefined) win.radius = o.radius;
            win.shellVolume = o.shellVolume !== undefined ? o.shellVolume : 1;
            win.draftPath = o.draft || "";
            win.bestsPath = o.bests || "";
            win.docsDir = o.docs || "";
            win.homeDir = o.home || "";
            sfxObj.manifest = o.sfx || {};

            var packs = Object.keys(o.sfx || {}).sort(function(a, b) {
                return a === "launcher" ? -1 : b === "launcher" ? 1 : a < b ? -1 : 1;
            });
            panel.packs = packs.concat(["none"]);
            panel.defaults = o.defaults || {};
            var v = {
                entrance: o.enter || "launcher", exit: o.exit || "launcher", colour: o.colour || "theme",
                bounce: o.bounce !== undefined ? o.bounce : 5, caret: o.caret || "bar",
                accent: o.accentKey || "mauve", size: o.size || 28, width: o.cols || 60,
                sparks: o.sparks === false ? "off" : "on", combo: o.combo === false ? "off" : "on",
                shake: o.shake || "enter", ripple: o.ripple ? "on" : "off",
                soundpack: o.pack || "launcher", volume: o.volume !== undefined ? o.volume : 10,
                ghost: o.ghost !== undefined ? o.ghost : 3, strict: o.strict ? "on" : "off",
                flow: o.flow || "follow", lead: o.lead || 0, autoline: o.autoline === false ? "off" : "on",
                grace: o.grace || 15,
                speed_time: o.speedTime || "60", speed_custom: o.speedCustom || 90, speed_text: o.speedText || "words",
                window: o.window || "window", keep: o.keep === false ? "off" : "on"
            };
            panel.values = v;
            for (var k in v) apply(k, v[k], true);

            readFile("snippets.json", function(s) {
                try { win.snippetList = JSON.parse(s); } catch (e) { win.snippetList = []; }
            });
            speed.load();

            openAnim.start();
            ed.forceActiveFocus();
            if (win.keep && win.draftPath) {
                readFile(win.draftPath, function(txt) { if (txt.length) setText(txt); win.ready = true; });
            } else {
                win.ready = true;
            }
        });
    }

    // one setting, from opts at start or live from the panel
    function apply(key, value, initial) {
        switch (key) {
        case "entrance": win.entrance = value; break;
        case "exit": win.exit = value; break;
        case "colour": win.colour = value; break;
        case "bounce": win.overshoot = Number(value) * 0.64; break;
        case "caret": win.caretStyle = value; break;
        case "accent": win.cAccent = win.pal[value] || win.pal.mauve || win.cAccent; break;
        case "size": win.userPx = Number(value); break;
        case "width": win.maxCols = Number(value); break;
        case "sparks": win.sparksOn = value === "on"; break;
        case "combo": win.comboOn = value === "on"; break;
        case "shake": win.shake = value; break;
        case "ripple": win.ripple = value === "on"; break;
        case "soundpack":
            // the default pack is already "launcher", and setting a property to
            // the value it has fires no change signal — so load it by hand
            if (sfxObj.pack === value) sfxObj.load(); else sfxObj.pack = value;
            if (!initial) demoTune.restart();
            break;
        case "volume": sfxObj.volume = Math.max(0, Math.min(1, win.shellVolume * Number(value) / 10)); break;
        case "ghost": win.ghostLevel = Number(value); break;
        case "strict": win.strict = value === "on"; break;
        case "flow":
            win.flow = value;
            if (win.followWait) { win.followWait = false; }
            break;
        case "lead": win.lead = Number(value); break;
        case "autoline": win.autoline = value === "on"; break;
        case "grace": win.grace = Number(value); break;
        case "speed_time": win.speedTime = String(value); if (!initial && win.mode === "speed") Qt.callLater(win.startSpeed); break;
        case "speed_custom": win.speedCustom = Number(value); if (!initial && win.mode === "speed") Qt.callLater(win.startSpeed); break;
        case "speed_text": win.speedText = value; if (!initial && win.mode === "speed") Qt.callLater(win.startSpeed); break;
        case "window":
            win.visibility = value === "fullscreen" ? Window.FullScreen
                           : value === "maximized" ? Window.Maximized : Window.Windowed;
            break;
        case "keep": win.keep = value === "on"; break;
        }
    }

    // a few notes so a sound pack can be heard the moment it is picked
    Timer {
        id: demoTune
        property int n: 0
        interval: 110
        repeat: true
        onRunningChanged: if (running) n = 0
        onTriggered: {
            var word = "bitewrite";
            if (n < word.length) sfxObj.play("key", word[n]);
            else { sfxObj.play("enter"); stop(); }
            n++;
        }
    }

    // ── layout ──────────────────────────────────────────────────────────────
    function isHigh(c) { return c >= 0xD800 && c <= 0xDBFF; }
    function isLow(c) { return c >= 0xDC00 && c <= 0xDFFF; }
    function glyphAt(s, i) {
        var code = s.charCodeAt(i), ch = s[i];
        if (isHigh(code)) return i + 1 < s.length ? ch + s[i + 1] : "";
        if (isLow(code) || ch === "\n" || ch === "\t" || ch === " " || ch === win.fill) return "";
        return ch;
    }

    // WRITE wraps words on a monospace grid (spaces hang off the end of a
    // line, a word that won't fit hops down whole). Everything else keeps its
    // lines as they are and the page scrolls sideways instead.
    function layout(s) {
        var n = s.length, c = new Array(n), r = new Array(n);
        var C = win.cols, col = 0, row = 0, i = 0, k, wrap = !win.nowrap;
        while (i < n) {
            var ch = s[i];
            if (ch === "\n") { c[i] = col; r[i] = row; row++; col = 0; i++; continue; }
            if (!wrap) {
                if (isLow(s.charCodeAt(i))) { c[i] = Math.max(0, col - 1); r[i] = row; i++; continue; }
                c[i] = col; r[i] = row; col++; i++; continue;
            }
            if (ch === " " || ch === "\t") { c[i] = Math.min(col, C); r[i] = row; col++; i++; continue; }
            var j = i, w = 0;
            while (j < n && s[j] !== " " && s[j] !== "\n" && s[j] !== "\t") {
                if (!isLow(s.charCodeAt(j))) w++;
                j++;
            }
            if (col > 0 && col + w > C) { row++; col = 0; }
            for (k = i; k < j; k++) {
                if (isLow(s.charCodeAt(k))) { c[k] = Math.max(0, col - 1); r[k] = row; continue; }
                if (col >= C) { row++; col = 0; }
                c[k] = col; r[k] = row; col++;
            }
            i = j;
        }
        return { c: c, r: r, ec: wrap ? Math.min(col, C) : col, er: row };
    }

    function widest(s) {
        var m = 0, lines = s.split("\n");
        for (var i = 0; i < lines.length; i++) m = Math.max(m, lines[i].length);
        return m;
    }
    function alignNow(s) {
        if (!win.ghosted) return null;
        return win.slotMode ? Align.slots(s, win.ghostLines) : Align.align(s, win.ghostLines);
    }
    function applyAlign(al) {
        win.ghostView = al ? al.view : [];
        win.wrong = al ? al.wrong : 0;
        win.alignComplete = al ? al.complete : false;
        speed.correct = al ? al.correct : 0;
    }

    // Diff the TextEdit against what is on screen — Input.qml's syncModel,
    // in two dimensions.
    function sync() {
        var s = ed.text, old = win.units, on = old.length, nn = s.length;
        var p = 0;
        while (p < on && p < nn && old[p] === s[p]) p++;
        var q = 0;
        while (q < on - p && q < nn - p && old[on - 1 - q] === s[nn - 1 - q]) q++;
        var del = on - p - q, ins = nn - p - q;
        if (del === 0 && ins === 0) return null;

        if (del > 0) {
            ghostOut(p, del);
            charModel.remove(p, del);
        }

        var L = layout(s), i;
        var al = win.alignNow(s);
        var bad = al ? al.bad : null;
        var move = function(idx, oc, orow, ob) {
            var nb = bad ? bad[idx] : false;
            if (oc !== L.c[idx]) charModel.setProperty(idx, "px", L.c[idx]);
            if (orow !== L.r[idx]) charModel.setProperty(idx, "py", L.r[idx]);
            if (!!ob !== nb) charModel.setProperty(idx, "bad", nb);
        };
        for (i = 0; i < p; i++) move(i, win.pc[i], win.pr[i], win.badArr[i]);

        // a paste, a restored page or a mode switch sweeps in as a wave; a
        // keystroke lands immediately
        var span = ins > 1 ? Math.min(1400, ins * 9) : 0;
        var rows = [];
        for (i = 0; i < ins; i++) {
            var at = p + i;
            rows.push({ g: glyphAt(s, at), px: L.c[at], py: L.r[at], bad: bad ? bad[at] : false,
                        born: ins > 1 ? Math.round(i / ins * span) : 0 });
        }
        if (p === charModel.count) charModel.append(rows);
        else for (i = 0; i < rows.length; i++) charModel.insert(p + i, rows[i]);

        for (i = p + ins; i < nn; i++) {
            var oi = i - ins + del;
            move(i, win.pc[oi], win.pr[oi], win.badArr[oi]);
        }
        if (p > 0) charModel.setProperty(p - 1, "g", glyphAt(s, p - 1));

        win.units = s.split("");
        win.pc = L.c; win.pr = L.r; win.badArr = bad || [];
        win.endCol = L.ec; win.endRow = L.er;
        win.typedMax = al ? al.widest : widest(s);
        applyAlign(al);
        return { p: p, ins: ins, del: del, text: s.substr(p, ins) };
    }

    // the ghost changed but the text didn't (a new piece, SPEED growing)
    function realign() {
        var s = ed.text, al = win.alignNow(s);
        for (var i = 0; i < s.length; i++) {
            var nb = al ? al.bad[i] : false;
            if (!!win.badArr[i] !== nb) charModel.setProperty(i, "bad", nb);
        }
        win.badArr = al ? al.bad : [];
        applyAlign(al);
    }

    function relayout() {
        var s = ed.text, L = layout(s);
        for (var i = 0; i < s.length; i++) {
            if (win.pc[i] !== L.c[i]) charModel.setProperty(i, "px", L.c[i]);
            if (win.pr[i] !== L.r[i]) charModel.setProperty(i, "py", L.r[i]);
        }
        win.pc = L.c; win.pr = L.r; win.endCol = L.ec; win.endRow = L.er;
        realign();
        updateCaret();
        updateSelection();
    }
    onColsChanged: Qt.callLater(win.relayout)

    function center(i) {
        var c = i < win.pc.length ? win.pc[i] : win.endCol, r = i < win.pr.length ? win.pr[i] : win.endRow;
        return { x: win.padX + c * win.slot + win.charW / 2, y: r * win.lineH + win.lineH / 2 };
    }

    // deleted letters get a stand-in that plays the exit where they stood —
    // only the ones on screen, so clearing a long page stays cheap
    function ghostOut(from, count) {
        var made = 0;
        for (var i = from; i < from + count && made < 400; i++) {
            var it = rep.itemAt(i);
            if (!it || it.glyph === "" || !win.near(win.pr[i])) continue;
            win.ghostComp.createObject(content, {
                w: win, style: win.exit, glyph: it.glyph, x: it.x, y: it.y,
                rise: it.rise + it.bump, scale: it.scale, rotation: it.rotation, color: it.color
            });
            if (win.exit === "dust" && made < 40) sparkAt(it.x + win.charW / 2, it.y + win.lineH / 2 + it.rise, 6);
            made++;
        }
    }

    function updateCaret() {
        var k = ed.cursorPosition;
        if (k >= win.units.length) { win.caretCol = win.endCol; win.caretRow = win.endRow; }
        else { win.caretCol = win.pc[k]; win.caretRow = win.pr[k]; }
        caret.opacity = 1;
        blink.restart();
        follow();
    }

    function updateSelection() {
        var a = Math.min(ed.selectionStart, ed.selectionEnd), b = Math.max(ed.selectionStart, ed.selectionEnd);
        var segs = [], cur = null;
        for (var i = a; i < b && i < win.units.length; i++) {
            if (win.units[i] === "\n") continue;
            if (!cur || cur.row !== win.pr[i]) { cur = { row: win.pr[i], c0: win.pc[i], c1: win.pc[i] + 1 }; segs.push(cur); }
            else cur.c1 = Math.max(cur.c1, win.pc[i] + 1);
        }
        win.selSegs = segs;
    }

    // keep the caret in view — down, and sideways for lines that don't wrap
    function follow() {
        var top = win.caretRow * win.lineH, pad = win.lineH;
        var ty = flick.contentY;
        if (top - pad < flick.contentY) ty = Math.max(0, top - pad);
        else if (top + win.lineH + pad > flick.contentY + flick.height) ty = top + win.lineH + pad - flick.height;
        ty = Math.max(0, Math.min(ty, Math.max(0, flick.contentHeight - flick.height)));
        if (Math.abs(ty - flick.contentY) > 0.5) { scrollAnim.to = ty; scrollAnim.restart(); }

        // sideways only when a line really is wider than the page — otherwise
        // reaching the end of a row nudged the whole page off its left edge
        var cx = win.padX + win.caretCol * win.slot, m = win.slot * 6, tx = flick.contentX;
        if (!win.nowrap || flick.contentWidth <= flick.width + 1) tx = 0;
        else if (cx - m < flick.contentX) tx = Math.max(0, cx - m);
        else if (cx + m > flick.contentX + flick.width) tx = cx + m - flick.width;
        tx = Math.max(0, Math.min(tx, Math.max(0, flick.contentWidth - flick.width)));
        if (Math.abs(tx - flick.contentX) > 0.5) { hScrollAnim.to = tx; hScrollAnim.restart(); }
    }

    function indexAt(px, py) {
        var row = Math.floor(py / win.lineH), col = (px - win.padX) / win.slot;
        var n = win.units.length, best = n, bestD = 1e9;
        for (var k = 0; k <= n; k++) {
            var r = k < n ? win.pr[k] : win.endRow, c = k < n ? win.pc[k] : win.endCol;
            if (r !== row) continue;
            var d = Math.abs(c - col);
            if (d < bestD) { bestD = d; best = k; }
        }
        if (bestD === 1e9 && row < win.endRow)
            for (k = 0; k < n; k++) if (win.pr[k] > row) return Math.max(0, k - 1);
        return best;
    }

    function setText(s) {
        win.quiet = true;
        ed.text = s;
        ed.cursorPosition = ed.length;
        win.quiet = false;
        win.complete = false;
    }

    // ── a key about to be typed ─────────────────────────────────────────────
    // Called for every printable key (and Enter) before the editor sees it.
    // true = handled here, don't type it as it is.
    function typeKey(t) {
        if (ed.readOnly) return true;
        var atEnd = ed.cursorPosition === ed.length && !ed.selectedText.length;

        if (win.slotMode) return win.slotKey(t);

        // strict: a wrong key is refused, not typed
        if (win.strict && win.ghosted && atEnd && win.mode !== "speed") {
            var want = Align.expected(Align.state(ed.text, win.ghostLines));
            if (want && t !== want && !(t === " " && want === "\n")) {
                sfxObj.play("error");
                shakePage(2.5);
                caretShake.restart();
                return true;
            }
        }

        // CODE with no ghost: a closing brace on an empty indented line
        // steps back out one level, like any editor
        if (win.mode === "code" && !win.ghosted && t === "}") {
            var s = ed.text, i = ed.cursorPosition, ls = s.lastIndexOf("\n", i - 1) + 1, before = s.substring(ls, i);
            if (before.length >= 2 && /^\s+$/.test(before)) {
                win.quiet = true;
                ed.remove(i - 2, i);
                win.quiet = false;
            }
        }
        return false;
    }

    // ── LYRICS and SPEED: every key fills the next slot ─────────────────────
    // The line never moves. A wrong letter stays red where it stands and you
    // carry on; extra letters are refused rather than shoving the ghost along
    // and off the screen; a space mid-word skips to the next word.
    // must match FILL in align.js — a .pragma library's plain vars don't
    // reach QML (only its functions do), so Align.FILL reads as undefined.
    // Private-use, because TextEdit turns a non-breaking space back into a
    // plain one the moment it's typed, which silently erased every skip
    readonly property string fill: "\ue000"
    function caretToEnd() { if (win.slotMode && !ed.selectedText.length) ed.cursorPosition = ed.length; }
    function refuse() {
        sfxObj.play("error");
        caretShake.restart();
        if (win.mode === "speed") speed.onKey("error");
    }
    function slotKey(t) {
        if (ed.selectedText.length) ed.deselect();
        ed.cursorPosition = ed.length;
        var s = ed.text, lines = s.split("\n"), r = lines.length - 1, line = lines[r], L = line.length;
        var last = r >= win.ghostLines.length - 1;
        var g = r < win.ghostLines.length ? win.ghostLines[r] : "";
        var gc = L < g.length ? g[L] : null;              // null: this row is full
        var wraps = win.mode === "speed" || win.autoline;
        var end = ed.length;

        if (t === "\n") {                                  // Enter skips the rest of the row
            if (last) { refuse(); return true; }
            ed.insert(end, g.substr(L).replace(/[^ ]/g, win.fill) + "\n");
            return true;
        }
        if (gc === null) {                                 // the row is full
            if (!wraps || last) { refuse(); return true; }
            ed.insert(end, t === " " ? "\n" : "\n" + t);
            return true;
        }
        if (t === " ") {
            if (gc === " ") return false;                  // the space it wants
            if (!L || line[L - 1] === " ") return true;    // a stray space between words: nothing happens
            var e = L;                                     // mid-word: skip the rest of the word
            while (e < g.length && g[e] !== " ") e++;
            var skip = g.substring(L, e).replace(/./g, win.fill);
            ed.insert(end, skip + (e < g.length ? " " : (wraps && !last ? "\n" : "")));
            return true;
        }
        if (gc === " ") { refuse(); return true; }         // the word is full — extras push nothing
        if (win.strict && t !== gc) { refuse(); return true; }
        return false;                                      // typed where it stands; wrong goes red
    }
    // Backspace straight after a skip takes the whole skip back in one press
    function slotBack() {
        var s = ed.text, n = s.length;
        if (!n || (s[n - 1] !== " " && s[n - 1] !== "\n")) return false;
        var j = n - 1;
        while (j > 0 && (s[j - 1] === win.fill || s[j - 1] === " ")) j--;
        if (s.substring(j, n).indexOf(win.fill) < 0) return false;
        ed.remove(j, n);
        return true;
    }

    // ── what a keystroke does besides the letter ────────────────────────────
    function onEdit(ch) {
        var kind = "key", c = "";
        if (ch.del > 0 && ch.ins === 0) kind = "back";
        else if (ch.ins >= 1) {
            c = ch.text.slice(-1);
            kind = c === "\n" ? "enter" : c === " " ? "space" : "key";
            if (win.ghosted && win.badArr[ch.p + ch.ins - 1]) kind = "error";
        }
        sfxObj.play(kind, c);

        if (ch.ins >= 1 && ch.ins <= 4) {
            var at = center(ch.p + ch.ins - 1);
            if (win.sparksOn && kind !== "enter" && kind !== "back") sparkAt(at.x, at.y, kind === "error" ? 3 : 7);
            if (win.ripple && ch.ins === 1) {
                for (var k = 1; k <= 7; k++) {
                    var it = rep.itemAt(ch.p - k);
                    if (!it || win.pr[ch.p - k] !== win.pr[ch.p]) break;
                    it.kick(k * 26);
                }
            }
            bumpCombo();
        }
        if (win.shake === "keys") shakePage(kind === "enter" ? 6 : 1.6);
        else if (win.shake === "enter" && kind === "enter") shakePage(5);

        if (win.mode === "code" && kind === "enter") autoIndent();
        if (win.mode === "code") compileCheck.restart();
        if (win.mode === "lyrics") songAlive();
        if (win.mode === "speed") {
            if (ch.ins >= 1) speed.onKey(kind);
            var typedRows = win.endRow;
            if (win.ghostLines.length - typedRows < 4) extendSpeed();
        }
        checkComplete();
    }

    // CODE: Enter lands on the next line already indented — like the ghost
    // when there is one, otherwise like the line above, one deeper after a {
    function autoIndent() {
        var i = ed.cursorPosition, s = ed.text;
        var before = s.substr(0, i).split("\n"), row = before.length - 1, pad = "";
        if (win.ghosted && row < win.ghostLines.length) {
            var g = win.ghostLines[row];
            pad = g.substr(0, g.length - g.replace(/^\s+/, "").length);
        } else if (!win.ghosted) {
            var prev = row > 0 ? before[row - 1] : "";
            pad = prev.substr(0, prev.length - prev.replace(/^\s+/, "").length);
            if (/[{\[(]\s*$/.test(prev)) pad += "  ";
        }
        if (pad.length && s.substr(i, pad.length) !== pad) {
            win.quiet = true;
            ed.insert(i, pad);
            win.quiet = false;
        }
    }

    function checkComplete() {
        if (!win.ghosted || win.mode === "speed") return;
        var done = win.alignComplete;
        if (done && !win.complete) {
            win.complete = true;
            sfxObj.play("done");
            celebrate();
            toast(win.mode === "code" ? "✓ it matches — ctrl+enter runs it" : "✓ you wrote the whole song");
            if (win.mode === "lyrics") graceTimer.stop();
        } else if (!done) {
            win.complete = false;
        }
    }

    function celebrate() {
        for (var i = 0; i < charModel.count; i++) {
            var it = rep.itemAt(i);
            if (it && win.near(win.pr[i])) it.celebrate((win.pc[i] + win.pr[i] * 3) * 14);
        }
        shakePage(8);
        for (var k = 0; k < 6; k++) sparkAt(flick.contentX + Math.random() * flick.width, flick.contentY + Math.random() * flick.height, 14);
    }

    // CODE: does what you've written compile? (said in the header, quietly)
    Timer {
        id: compileCheck
        interval: 350
        onTriggered: win.compileState = ed.text.trim().length ? stage.check(ed.text) : null
    }

    // ── combo ───────────────────────────────────────────────────────────────
    property int combo: 0
    property int bestCombo: 0
    property real lastKey: 0
    readonly property var milestones: [10, 25, 50, 100, 200, 400, 800]
    function bumpCombo() {
        if (!win.comboOn) return;
        var now = Date.now();
        win.combo = now - win.lastKey < 900 ? win.combo + 1 : 1;
        win.lastKey = now;
        win.bestCombo = Math.max(win.bestCombo, win.combo);
        comboDecay.restart();
        comboPulse.restart();
        // milestones are seen, not heard — a chime at letter 10, 25, 50
        // lands mid-sentence and reads as a random jingle over the typing
        if (win.milestones.indexOf(win.combo) >= 0) {
            shakePage(7);
            var p = comboText.mapToItem(content, comboText.width / 2, comboText.height / 2);
            sparkAt(p.x, p.y, 30);
            toast(win.combo + " combo");
        }
    }
    Timer { id: comboDecay; interval: 1100; onTriggered: win.combo = 0 }

    // ── lyrics: your typing plays the song ──────────────────────────────────
    property var song: null            // the picked item
    property var lyricLines: []        // [{t, text}] from the engine
    property var lyricRows: []         // first ghost row of each lyric line
    property bool synced: false
    property bool songPlaying: false
    property bool followWait: false    // follow: the song is waiting for you
    property real songPos: 0
    property var nowInfo: null
    property var media: null
    property int sungRow: -1
    property int sungRowEnd: -1

    function makeMedia() {
        if (win.media) return win.media;
        try {
            win.media = Qt.createQmlObject('import QtMultimedia; MediaPlayer { audioOutput: AudioOutput { volume: 0 } }', win, "media");
        } catch (e) {
            toast("song playback needs qt6-multimedia");
        }
        return win.media;
    }

    readonly property bool followOn: win.flow === "follow" && win.synced
    function lyricLineOfRow(r) {
        var idx = 0;
        for (var i = 0; i < win.lyricRows.length; i++) if (win.lyricRows[i] <= r) idx = i;
        return idx;
    }

    function songAlive() {
        if (!win.song) return;
        if (!win.songPlaying && !win.followWait) songPlay();
        // drive — and follow without timestamps, which can't know where the singer is
        if ((win.flow === "drive" || (win.flow === "follow" && !win.synced)) && !win.complete) graceTimer.restart();
    }
    function songPlay() {
        win.songPlaying = true;
        if (win.song.kind === "file") {
            var m = makeMedia(); if (!m) return;
            m.play();
            fade.stop(); fade.target = m.audioOutput; fade.to = 1; fade.duration = 250; fade.start();
        } else {
            ask({ action: "player", player: win.song.player, op: "play" }, null);
        }
    }
    function songPause() {
        if (!win.song || !win.songPlaying) return;
        win.songPlaying = false;
        if (win.song.kind === "file" && win.media) {
            fade.stop(); fade.target = win.media.audioOutput; fade.to = 0; fade.duration = win.followWait ? 250 : 600; fade.start();
        } else {
            ask({ action: "player", player: win.song.player, op: "pause" }, null);
        }
    }
    function songStop() {
        if (!win.song) return;
        win.followWait = false;
        songPause();
        ask({ action: "watch", player: "" }, null);
        win.song = null;
    }
    NumberAnimation {
        id: fade
        property: "volume"
        easing.type: Easing.InOutSine
        onFinished: if (!win.songPlaying && win.media) win.media.pause()
    }
    Timer {
        id: graceTimer
        interval: win.grace * 100
        onTriggered: songPause()
    }

    // where the singer is: the karaoke highlight, and follow's waiting
    Timer {
        interval: 120
        repeat: true
        running: win.mode === "lyrics" && win.song !== null
        onTriggered: {
            if (win.song.kind === "file") {
                if (win.media) win.songPos = win.media.position / 1000;
            } else {
                readFile("now.json", function(raw) {
                    try { win.nowInfo = JSON.parse(raw); } catch (e) { return; }
                });
                var n = win.nowInfo;
                if (n && n.ok) win.songPos = n.pos + (n.status === "Playing" ? Date.now() / 1000 - n.at : 0);
            }
            if (!win.synced) { win.sungRow = -1; return; }
            var idx = -1;
            for (var i = 0; i < win.lyricLines.length; i++) if (win.lyricLines[i].t <= win.songPos + 0.15) idx = i;
            win.sungRow = idx >= 0 ? win.lyricRows[idx] : -1;
            win.sungRowEnd = idx >= 0 ? (idx + 1 < win.lyricRows.length ? win.lyricRows[idx + 1] - 1 : win.ghostLines.length - 1) : -1;

            // follow: the song may play up to the start of the line after
            // yours (plus the lead), and waits there until you arrive
            if (win.followOn && !win.complete) {
                var next = lyricLineOfRow(win.caretRow) + 1 + win.lead;
                var gate = next < win.lyricLines.length ? win.lyricLines[next].t : 1e9;
                if (win.songPlaying && win.songPos >= gate - 0.1) {
                    win.followWait = true;
                    songPause();
                } else if (win.followWait && win.songPos < gate - 0.1) {
                    win.followWait = false;
                    songPlay();
                }
            }
        }
    }

    function normalizeLyric(s) {
        return s.toLowerCase().replace(/[’‘`´]/g, "'").replace(/[—–-]/g, " ")
                .replace(/[.,!?;:"“”()\[\]…*]/g, "").replace(/\s+/g, " ").trim();
    }

    function openLyrics(item) {
        toast("finding the lyrics…");
        ask(item.kind === "file" ? { action: "lyrics", kind: "file", path: item.path }
                                 : { action: "lyrics", kind: "player", player: item.player, artist: item.artist,
                                     title: item.title, album: item.album, length: item.length },
            function(r) {
                if (!r.ok) { toast(r.error || "no lyrics found"); return; }
                songStop();
                var C = Math.max(20, win.fitColsAt(win.userPx)), rows = [], starts = [];
                win.lyricLines = r.lines.filter(function(l) { return normalizeLyric(l.text).length; });
                win.lyricLines.forEach(function(l) {
                    starts.push(rows.length);
                    var words = normalizeLyric(l.text).split(" "), line = "";
                    words.forEach(function(wd) {
                        if (line.length && line.length + 1 + wd.length > C) { rows.push(line); line = wd; }
                        else line = line.length ? line + " " + wd : wd;
                    });
                    rows.push(line);
                });
                win.lyricRows = starts;
                win.synced = r.synced;
                win.song = item;
                if (item.kind === "file") { var m = makeMedia(); if (m) { m.source = "file://" + encodeURI(item.path); m.audioOutput.volume = 0; } }
                else ask({ action: "watch", player: item.player }, null);
                var m2 = r.meta || {};
                win.pieceName = (m2.artist ? m2.artist + " — " : "") + (m2.title || item.title);
                startPiece(rows.join("\n"));
                var how = win.followOn ? "start typing — the song waits for you at every line"
                        : win.flow === "karaoke" ? "start typing, then race the singer"
                        : "start typing and the song plays";
                toast("lyrics from " + r.source + " — " + how);
            });
    }

    // ── modes ───────────────────────────────────────────────────────────────
    // The old letters are cleared BEFORE the mode changes: a mode change can
    // resize the font, and letters leaving afterwards played their exit in
    // the new size at the old spacing.
    function startPiece(t) {
        setText("");
        win.target = t;
        win.ghostLines = t.length ? t.split("\n") : [];
        win.ghostHidden = false;
        win.combo = 0;
        win.compileState = null;
        flick.contentX = 0;
        Qt.callLater(win.relayout);
        if (win.mode === "code") Qt.callLater(win.autoIndent);
    }

    function startSpeed() {
        startPiece(speed.generate());
    }
    function extendSpeed() {
        var more = speed.more();
        win.ghostLines = win.ghostLines.concat(more);
        win.target = win.target + "\n" + more.join("\n");
        realign();
    }
    function cycleSpeed(key, list, d) {
        var cur = key === "speed_time" ? win.speedTime : win.speedText;
        var i = list.indexOf(cur);
        setSetting(key, list[(i + d + list.length) % list.length]);
    }

    function setMode(m) {
        if (m === win.mode && m === "write") return;
        if (win.mode === "write") win.writeText = ed.text;
        if (win.mode === "lyrics" && m !== "lyrics") songStop();
        if (m === "write") {
            setText("");
            win.mode = "write";
            win.target = ""; win.ghostLines = []; win.pieceName = "";
            setText(win.writeText);
            Qt.callLater(win.relayout);
        } else if (m === "speed") {
            win.mode = "speed";
            win.pieceName = "";
            startSpeed();
        } else if (m === "code") {
            picker.open("CODE — pick something to type, or start blank", [
                { title: "✎ blank page", sub: "write your own — ctrl+enter runs whatever you wrote", tag: "free", blank: true }
            ].concat(win.snippetList.map(function(s) {
                return { title: s.name, sub: s.about, tag: s.level, snippet: s };
            })), "");
            picker.purpose = "code";
        } else if (m === "lyrics") {
            picker.open("LYRICS — pick a song", [], "looking for players and songs…");
            picker.purpose = "lyrics";
            ask({ action: "songs" }, function(r) {
                var items = (r.songs || []).map(function(s) {
                    return s.kind === "player"
                        ? { title: (s.artist ? s.artist + " — " : "") + s.title, sub: "in " + s.player + " · " + s.status.toLowerCase(),
                            tag: "now playing", song: s }
                        : { title: (s.artist ? s.artist + " — " : "") + s.title, sub: pretty(s.path),
                            tag: s.local ? "lyrics ✓" : "", song: s };
                });
                picker.setItems(items, items.length ? "" :
                    "nothing is playing and your music folder is empty. Play a song in Spotify, YouTube or mpv, then press F3 again — or drop audio files into ~/.local/share/bite-os/bitewrite/songs");
            });
        }
    }

    function pickerChosen(item) {
        if (win.mode === "write") win.writeText = ed.text;
        if (picker.purpose === "code") {
            if (win.mode === "lyrics") songStop();
            win.mode = "code";
            if (item.blank) {
                win.pieceName = "blank page";
                startPiece("");
                toast("write anything — ctrl+enter runs it (define function frame(t) and draw with ctx)");
            } else {
                win.pieceName = item.snippet.name;
                startPiece(item.snippet.code);
                toast("type it over the ghost, or change it — ctrl+enter runs whatever you wrote");
            }
        } else {
            win.mode = "lyrics";
            openLyrics(item.song);
        }
        ed.forceActiveFocus();
    }

    // runs exactly what's on the page: broken code doesn't run, valid code does
    function runCode() {
        if (!ed.text.trim().length) { toast("nothing to run yet"); sfxObj.play("error"); return; }
        var c = stage.check(ed.text);
        if (!c.ok) {
            toast("it doesn't compile — " + c.message + " · check brackets, quotes and commas");
            sfxObj.play("error");
            shakePage(4);
            return;
        }
        sfxObj.play("run");
        stage.run(ed.text);
    }

    // ── keeping what you wrote ──────────────────────────────────────────────
    Timer {
        id: keepTimer
        interval: 700
        onTriggered: if (win.keep && win.draftPath && win.mode === "write") win.writeFile(win.draftPath, ed.text)
    }
    property bool leaving: false
    function leave() {
        if (win.leaving) return;
        win.leaving = true;
        songStop();
        var page = win.mode === "write" ? ed.text : win.writeText;
        ask({ action: "quit" }, null);
        if (win.keep && win.draftPath) {
            win.writeFile(win.draftPath, page, function() { Qt.quit(); });
            quitGuard.start();
        } else {
            quitGuard.interval = 150; quitGuard.start();
        }
    }
    Timer { id: quitGuard; interval: 800; onTriggered: Qt.quit() }
    onClosing: function(close) { if (!win.leaving) { close.accepted = false; win.leave(); } }

    function pretty(path) {
        return win.homeDir && path.indexOf(win.homeDir) === 0 ? "~" + path.slice(win.homeDir.length) : path;
    }
    function saveCopy() {
        if (!ed.text.trim().length) { toast("nothing to save yet"); return; }
        var d = new Date(), z = function(v) { return (v < 10 ? "0" : "") + v; };
        var name = "bitewrite-" + d.getFullYear() + "-" + z(d.getMonth() + 1) + "-" + z(d.getDate()) + "-" +
                   z(d.getHours()) + z(d.getMinutes()) + z(d.getSeconds()) + (win.mode === "code" ? ".js" : ".txt");
        var path = (win.docsDir || win.homeDir) + "/" + name;
        // skipped letters are private-use marks on the page — spaces in a file
        win.writeFile(path, ed.text.split(win.fill).join(" "), function() { toast("saved → " + pretty(path)); });
        sfxObj.play("enter");
    }
    function toast(msg) { toastText.text = msg; toastAnim.restart(); }

    // ── feel ────────────────────────────────────────────────────────────────
    function sparkAt(x, y, n) { if (n > 0) burst.burst(n, x, y); }
    function shakePage(power) {
        shakeX1.to = (Math.random() - 0.5) * 2 * power; shakeY1.to = (Math.random() - 0.5) * 2 * power;
        shakeX2.to = (Math.random() - 0.5) * power; shakeY2.to = (Math.random() - 0.5) * power;
        shakeAnim.restart();
    }
    SequentialAnimation {
        id: shakeAnim
        ParallelAnimation {
            NumberAnimation { id: shakeX1; target: pageShift; property: "x"; duration: 45 }
            NumberAnimation { id: shakeY1; target: pageShift; property: "y"; duration: 45 }
        }
        ParallelAnimation {
            NumberAnimation { id: shakeX2; target: pageShift; property: "x"; duration: 60 }
            NumberAnimation { id: shakeY2; target: pageShift; property: "y"; duration: 60 }
        }
        ParallelAnimation {
            NumberAnimation { target: pageShift; property: "x"; to: 0; duration: 180; easing.type: Easing.OutBack }
            NumberAnimation { target: pageShift; property: "y"; to: 0; duration: 180; easing.type: Easing.OutBack }
        }
    }

    // ── the hidden editor ───────────────────────────────────────────────────
    TextEdit {
        id: ed
        x: 0; y: 0; width: 1; height: 1
        opacity: 0
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.NoWrap
        color: "transparent"
        selectionColor: "transparent"
        selectedTextColor: "transparent"
        font.family: win.fontFamily
        font.pixelSize: win.fontPx
        persistentSelection: true
        readOnly: win.mode === "speed" && speed.finished

        onTextChanged: {
            var ch = win.sync();
            if (!ch) return;
            win.updateCaret();
            win.updateSelection();
            if (!win.quiet) {
                win.onEdit(ch);
                keepTimer.restart();
            }
        }
        onCursorPositionChanged: {
            win.updateCaret();
            // slot typing always happens at the end — a click or an arrow
            // can't open a gap in the middle of the line
            if (win.slotMode && !ed.selectedText.length && ed.cursorPosition < ed.length) Qt.callLater(win.caretToEnd);
        }
        onSelectionStartChanged: win.updateSelection()
        onSelectionEndChanged: win.updateSelection()

        Keys.onPressed: function(e) {
            var ctrl = e.modifiers & Qt.ControlModifier;
            if (panel.handle(e)) { e.accepted = true; return; }
            var times = ["15", "30", "60", "120", "infinite", "custom"], texts = ["words", "sentences", "hard", "page"];

            // a finished SPEED run: the card is up and the page is locked
            if (win.mode === "speed" && speed.finished && !ctrl) {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.startSpeed();
                else if (e.key === Qt.Key_Tab) win.cycleSpeed("speed_time", times, 1);
                else if (e.key === Qt.Key_Backtab) win.cycleSpeed("speed_text", texts, 1);
                else if (e.key === Qt.Key_Escape) win.setMode("write");
                else if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F5) { /* fall through below */ }
                else { e.accepted = true; return; }
                if (e.key < Qt.Key_F1 || e.key > Qt.Key_F5) { e.accepted = true; return; }
            }

            if (e.key === Qt.Key_F1) win.setMode("write");
            else if (e.key === Qt.Key_F2) win.setMode("code");
            else if (e.key === Qt.Key_F3) win.setMode("lyrics");
            else if (e.key === Qt.Key_F4) win.setMode("speed");
            else if (e.key === Qt.Key_F5 || (ctrl && e.key === Qt.Key_Comma)) panel.open();
            else if (ctrl && e.key === Qt.Key_Q) win.leave();
            else if (e.key === Qt.Key_Escape) { if (win.mode !== "write") win.setMode("write"); else win.leave(); }
            else if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                if (win.mode === "code") win.runCode();
                else if (win.mode === "lyrics") { if (win.songPlaying) win.songPause(); else { win.followWait = false; win.songPlay(); } }
            }
            else if (ctrl && e.key === Qt.Key_R) {
                if (win.mode === "speed") win.startSpeed();
                else if (win.ghosted) win.startPiece(win.target);
            }
            else if (ctrl && e.key === Qt.Key_N) {
                if (win.mode === "speed") win.startSpeed();
                else if (win.mode !== "write") win.setMode(win.mode);
            }
            else if (ctrl && e.key === Qt.Key_H) win.ghostHidden = !win.ghostHidden;
            else if (ctrl && e.key === Qt.Key_S) win.saveCopy();
            else if (ctrl && e.key === Qt.Key_L) { if (ed.length) ed.remove(0, ed.length); }
            else if (ctrl && (e.key === Qt.Key_Equal || e.key === Qt.Key_Plus)) win.userPx = Math.min(72, win.userPx + 2);
            else if (ctrl && e.key === Qt.Key_Minus) win.userPx = Math.max(12, win.userPx - 2);
            else if (ctrl && e.key === Qt.Key_M) { sfxObj.muted = !sfxObj.muted; win.toast(sfxObj.muted ? "sound off" : "sound on"); }
            else if (e.key === Qt.Key_Backtab) { if (win.mode === "speed") win.cycleSpeed("speed_text", texts, 1); }
            else if (e.key === Qt.Key_Tab) {
                if (win.mode === "speed") win.cycleSpeed("speed_time", times, 1);
                else if (win.mode !== "lyrics") ed.insert(ed.cursorPosition, win.mode === "code" ? "  " : "    ");
            }
            else if (!ctrl && e.key === Qt.Key_Backspace && win.slotMode) { if (!win.slotBack()) return; }
            else if (!ctrl && e.text.length === 1 && e.text >= " ") { if (!win.typeKey(e.text)) return; }
            else if (!ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { if (!win.typeKey("\n")) return; }
            else return;
            e.accepted = true;
        }
    }

    // ── the page ────────────────────────────────────────────────────────────
    // the header spans the window, not the page — a ghost shrinks the page
    // to its longest line, and a narrow page crushed these together
    Row {
        id: tabs
        anchors.left: parent.left
        anchors.bottom: page.top
        anchors.bottomMargin: 12
        anchors.leftMargin: 28
        spacing: 18
        Repeater {
            model: [["write", "F1"], ["code", "F2"], ["lyrics", "F3"], ["speed", "F4"]]
            delegate: Text {
                readonly property bool on: win.mode === modelData[0]
                text: modelData[0].toUpperCase()
                font.family: win.fontFamily
                font.pixelSize: 13
                font.letterSpacing: 2
                color: on ? win.cAccent : win.cSub
                opacity: on ? 1 : 0.55
                Behavior on color { ColorAnimation { duration: 160 } }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.setMode(modelData[0]) }
            }
        }
        Text {
            text: "⚙"
            font.pixelSize: 14
            color: win.cSub
            opacity: 0.55
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.open() }
        }
    }

    Text {
        id: piece
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: page.top
        anchors.bottomMargin: 12
        width: Math.max(0, parent.width - 2 * Math.max(tabs.width, counts.width) - 120)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: win.mode !== "speed"
        text: win.pieceName + (win.mode === "lyrics" && win.song
              ? (win.followWait ? "   ‖ waiting for you" : win.songPlaying ? "   ♪" : "   ‖") : "")
        font.family: win.fontFamily
        font.pixelSize: 13
        color: win.followWait ? win.cAccent : win.cText
        opacity: 0.8
    }

    Text {
        id: counts
        readonly property int words: {
            var t = ed.text.trim();
            return t.length ? t.split(/\s+/).length : 0;
        }
        readonly property bool broken: win.mode === "code" && win.compileState !== null && !win.compileState.ok
        text: win.mode === "speed" ? "best " + (speed.bests[speed.bestKey] || "—")
            : win.mode === "code"
            ? (win.ghosted && win.wrong ? win.wrong + (win.wrong === 1 ? " word differs   ·   " : " words differ   ·   ") : "")
              + (win.compileState === null ? "" : win.compileState.ok ? "✓ compiles" : "✗ doesn't compile")
            : win.ghosted
            ? Math.min(ed.length, win.target.length) + " / " + win.target.length + (win.wrong ? "   ·   " + win.wrong + " wrong" : "")
            : counts.words + (counts.words === 1 ? " word" : " words") + "   ·   " + (win.endRow + 1) + (win.endRow === 0 ? " line" : " lines")
        anchors.right: parent.right
        anchors.bottom: page.top
        anchors.bottomMargin: 12
        anchors.rightMargin: 28
        font.family: win.fontFamily
        font.pixelSize: 13
        color: counts.broken || (win.mode !== "code" && win.wrong) ? win.cBad : win.cSub
        opacity: 0.75
    }

    Rectangle {
        id: page
        readonly property real comboHeat: win.comboOn ? Math.min(1, win.combo / 60) : 0
        width: Math.min(win.cols * win.slot + 2 * win.padX, win.width - 40)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 52
        anchors.bottomMargin: 58
        radius: win.radius * 1.6
        color: win.cPage
        border.width: 1 + page.comboHeat * 2
        border.color: win.mix(win.cEdge, win.cAccent, 0.25 + page.comboHeat * 0.75)
        clip: true
        opacity: 0
        scale: 0.97
        transform: Translate { id: pageShift }

        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

        // the launcher's focus pop, on the whole page when it opens
        SequentialAnimation {
            id: openAnim
            ParallelAnimation {
                NumberAnimation { target: page; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: page; property: "scale"; to: 1.03; duration: 110; easing.type: Easing.OutQuad }
            }
            NumberAnimation { target: page; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutQuint }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.topMargin: win.padY
            anchors.bottomMargin: win.padY
            // lines that don't wrap make the page scroll sideways, following
            // the caret, instead of running off the edge where you lose them
            contentWidth: win.nowrap ? Math.max(width, 2 * win.padX + (Math.max(win.longest, win.typedMax) + 1) * win.slot) : width
            contentHeight: Math.max(height, (Math.max(win.endRow, win.ghostLines.length) + 2) * win.lineH)
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { id: hScrollAnim; target: flick; property: "contentX"; duration: 240; easing.type: Easing.OutCubic }

            Item {
                id: content
                width: flick.contentWidth
                height: flick.contentHeight

                TapHandler {
                    onTapped: function(ev) {
                        ed.forceActiveFocus();
                        ed.deselect();
                        ed.cursorPosition = win.indexAt(ev.position.x, ev.position.y);
                    }
                }

                Text {
                    text: win.mode === "code" ? "write some code — define function frame(t) and draw with ctx" : "just write."
                    x: win.padX
                    height: win.lineH
                    verticalAlignment: Text.AlignVCenter
                    font.family: win.fontFamily
                    font.pixelSize: win.fontPx
                    color: win.cSub
                    opacity: win.ready && charModel.count === 0 && !win.ghosted ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }

                // the ghost: per row, only what's still to type, carrying on
                // from wherever that row's typing ends
                Repeater {
                    model: win.ghostView
                    delegate: Text {
                        readonly property bool sung: win.sungRow >= 0 && index >= win.sungRow && index <= win.sungRowEnd
                        x: win.padX + modelData.col * win.slot + (win.slot - win.charW) / 2
                        y: index * win.lineH
                        height: win.lineH
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.text
                        font.family: win.fontFamily
                        font.pixelSize: win.fontPx
                        font.letterSpacing: win.slot - win.charW
                        color: sung ? win.cAccent : win.cText
                        opacity: win.ghostHidden ? 0
                               : win.mode === "speed" ? 0.5
                               : (sung ? Math.max(0.55, win.ghostLevel / 10) : win.ghostLevel / 10 * 0.6)
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        // letters skipped with a space: still in their place, in red
                        Text {
                            text: modelData.missed || ""
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            font: parent.font
                            color: win.cBad
                            opacity: parent.opacity > 0.01 ? Math.min(1, 0.6 / parent.opacity) : 0
                        }
                    }
                }

                Repeater {
                    model: win.selSegs
                    delegate: Rectangle {
                        x: win.padX + modelData.c0 * win.slot - 2
                        width: (modelData.c1 - modelData.c0) * win.slot + 3
                        y: modelData.row * win.lineH + (win.lineH - height) / 2
                        height: win.fontPx * 1.5
                        radius: 4
                        color: win.cAccent
                        opacity: 0.28
                    }
                }

                Repeater {
                    id: rep
                    model: charModel
                    delegate: Glyph {
                        w: win
                        col: model.px
                        row: model.py
                        glyph: model.g
                        born: model.born
                        bad: model.bad
                    }
                }

                ParticleSystem { id: sparks; anchors.fill: parent; running: win.sparksOn || win.exit === "dust" || win.comboOn }
                ImageParticle {
                    system: sparks
                    source: "qrc:///particleresources/glowdot.png"
                    color: win.cAccent
                    colorVariation: win.colour === "rainbow" ? 1 : 0.25
                    alpha: 0.9
                    entryEffect: ImageParticle.Scale
                }
                Emitter {
                    id: burst
                    system: sparks
                    enabled: false
                    lifeSpan: 480
                    lifeSpanVariation: 160
                    size: Math.max(6, win.fontPx * 0.32)
                    sizeVariation: 3
                    endSize: 1
                    velocity: AngleDirection { angleVariation: 360; magnitude: 110; magnitudeVariation: 70 }
                    acceleration: PointDirection { y: 260 }
                }

                Rectangle {
                    id: caret
                    readonly property bool bar: win.caretStyle === "bar"
                    width: bar ? 2 : win.charW
                    height: win.caretStyle === "underline" ? 3 : win.fontPx * (bar ? 1.2 : 1.35)
                    radius: 1
                    color: win.cAccent
                    visible: ed.activeFocus && win.ready && !ed.readOnly
                    x: win.padX + win.caretCol * win.slot - (bar ? 1 : 0) + caretJolt.x
                    y: win.caretRow * win.lineH + (win.caretStyle === "underline" ? win.lineH / 2 + win.fontPx * 0.62 : (win.lineH - height) / 2)
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    Item { id: caretJolt }
                    SequentialAnimation {
                        id: caretShake
                        NumberAnimation { target: caretJolt; property: "x"; to: -5; duration: 40 }
                        NumberAnimation { target: caretJolt; property: "x"; to: 5; duration: 40 }
                        NumberAnimation { target: caretJolt; property: "x"; to: 0; duration: 60 }
                    }
                    SequentialAnimation {
                        id: blink
                        running: caret.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: 500 }
                        NumberAnimation { target: caret; property: "opacity"; to: caret.bar ? 0 : 0.15; duration: 100; easing.type: Easing.InQuad }
                        PauseAnimation { duration: 400 }
                        NumberAnimation { target: caret; property: "opacity"; to: caret.bar ? 1 : 0.55; duration: 100; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        Text {
            id: comboText
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            text: "×" + win.combo
            font.family: win.fontFamily
            font.pixelSize: 18 + Math.min(22, win.combo / 5)
            font.bold: true
            color: win.mix(win.cSub, win.cAccent, page.comboHeat)
            opacity: win.comboOn && win.combo >= 3 ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            SequentialAnimation {
                id: comboPulse
                NumberAnimation { target: comboText; property: "scale"; to: 1.25; duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: comboText; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
            }
        }
    }

    // ── footer ──────────────────────────────────────────────────────────────
    Text {
        id: hints
        text: win.mode === "code"
            ? "ctrl+enter run what you wrote   ·   ctrl+n another   ·   ctrl+r restart   ·   ctrl+h hide ghost   ·   f5 settings   ·   esc back"
            : win.mode === "lyrics"
            ? "ctrl+enter play / pause   ·   ctrl+n another song   ·   ctrl+r restart   ·   f5 settings   ·   esc back"
            : "f2 code   ·   f3 lyrics   ·   f4 speed   ·   f5 settings   ·   ctrl+s save   ·   ctrl+l clear   ·   esc close"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: page.bottom
        anchors.topMargin: 18
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        font.family: win.fontFamily
        font.pixelSize: 12
        color: win.cSub
        opacity: win.mode === "speed" || toastText.opacity > 0 ? 0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
    Text {
        id: toastText
        anchors.horizontalCenter: parent.horizontalCenter
        // SPEED keeps its live stats where the hints go, so toasts sit inside
        // the bottom of the page there instead
        y: win.mode === "speed" ? page.y + page.height - 36 : hints.y
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        font.family: win.fontFamily
        font.pixelSize: 13
        color: win.cAccent
        opacity: 0
        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toastText; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 2600 }
            NumberAnimation { target: toastText; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InCubic }
        }
    }

    // ── overlays ────────────────────────────────────────────────────────────
    Speed {
        id: speed
        w: win
        page: page
        leftLimit: tabs.x + tabs.width + 32
    }

    Panel {
        id: panel
        w: win
        onChanged: function(key, value) {
            win.apply(key, value, false);
            var d = win.dirty; d[key] = String(value); win.dirty = d;
            saveSettings.restart();
        }
    }

    Picker {
        id: picker
        w: win
        property string purpose: ""
        onChosen: function(item) { win.pickerChosen(item); }
        onCancelled: ed.forceActiveFocus()
    }

    Stage {
        id: stage
        w: win
        anchors.fill: parent
        onStopped: ed.forceActiveFocus()
        onFailed: function(msg, line) {
            win.toast((line > 0 ? "line " + line + ": " : "") + msg);
            sfxObj.play("error");
            ed.forceActiveFocus();
        }
    }
}
