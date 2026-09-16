// bitewrite — the launcher's search box, turned into a whole page.
//
// Five modes behind one page:
//   WRITE   free writing, kept between sessions
//   NOTES   as many notes as you like, saved as you type
//   CODE    write a program in JavaScript, Python or Bash (or type one over
//           its ghost); Ctrl+Enter runs whatever you wrote
//   LYRICS  a song's lyrics as the ghost; your typing drives the song
//   SPEED   a typing test with your speed live at the bottom
//
// A hidden TextEdit owns the text (typing, undo, paste, the keyboard caret
// all come free) and every character is its own Glyph on a monospace grid,
// fed by a prefix/suffix diff so only changed letters are born or die.
// bidi.js puts right-to-left text where it belongs on that grid; align.js
// holds what you type against the ghost. Animation numbers for the default
// style are lifted from serpantinum's reusables/Input.qml, so it FEELS like
// the launcher rather than resembling it.

import QtQuick
import QtQuick.Window
import QtQuick.Particles
import "align.js" as Align
import "bidi.js" as Bidi

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
    property string fontRtl: ""
    property real radius: 10
    property int userPx: 28
    property int maxCols: 60
    property string direction: "auto"
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
    property string terminalName: ""
    property var snippetList: []
    property bool ready: false
    property var sfx: sfxObj

    // ── mode ────────────────────────────────────────────────────────────────
    property string mode: "write"
    property string target: ""         // the ghost, in CODE, LYRICS and SPEED
    property var ghostLines: []
    property var ghostVis: []          // per ghost line: where each letter sits (bidi.js)
    property int ghostCells: 0
    property var ghostView: []         // align.js's view of the ghost, per row
    property string writeText: ""      // WRITE's page while another mode is up
    property string pieceName: ""
    property string codeLang: "js"
    property bool ghostHidden: false
    property bool complete: false
    property bool alignComplete: false
    property int wrong: 0
    property int typedMax: 0
    property var compileState: null
    readonly property bool ghosted: win.mode !== "write" && win.mode !== "notes" && win.target.length > 0
    // code never wraps (a wrapped line of code is a different line of code),
    // and neither does anything with a ghost, so typing sits on top of it
    readonly property bool nowrap: win.ghosted || win.mode === "code"
    // LYRICS and SPEED: every key fills the next slot of the ghost and the
    // line never moves (see align.js slots())
    readonly property bool slotMode: win.ghosted && (win.mode === "lyrics" || win.mode === "speed")
    readonly property var langNames: ({ js: "javascript", python: "python", bash: "bash" })

    // ── grid ────────────────────────────────────────────────────────────────
    readonly property int longest: win.ghostCells
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
    readonly property real sideRoom: notes.active && win.width > 900 ? 260 : 0
    readonly property int fitCols: Math.max(8, Math.floor((win.width - 96 - win.sideRoom - 2 * win.padX) / win.slot))
    readonly property int cols: win.ghosted ? Math.max(win.longest + 1, 8)
                              : (win.mode === "code" ? win.fitCols : Math.min(win.maxCols, win.fitCols))
    function fitColsAt(px) { return Math.floor((win.width - 150) / (px * 0.62)) - 3; }

    property var units: []
    property var pc: []          // column of each character's cell
    property var pr: []          // row
    property var pg: []          // what's drawn for it (mirrored brackets, whole clusters)
    property var pw: []          // cells it takes
    property var pf: []          // drawn in the right-to-left font
    property var cc: []          // where the caret sits before each index (n+1)
    property var cr: []
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
    ListModel { id: ghostModel }
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
                if (!win.waiting) sendNext();
                return;
            }
            readFile("status.json", function(raw) {
                var r; try { r = JSON.parse(raw); } catch (e) { return; }
                if (!win.waiting || r.seq !== win.waiting.seq) return;
                var w0 = win.waiting; win.waiting = null;
                if (w0.cb) w0.cb(r);
                // a callback that asks again has already sent its request —
                // sending "next" now would forget that one was in flight
                if (!win.waiting) sendNext();
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
            win.fontRtl = o.fontRtl || "";
            if (o.radius !== undefined) win.radius = o.radius;
            win.shellVolume = o.shellVolume !== undefined ? o.shellVolume : 1;
            win.draftPath = o.draft || "";
            win.bestsPath = o.bests || "";
            win.docsDir = o.docs || "";
            win.homeDir = o.home || "";
            win.terminalName = o.terminal || "";
            notes.dir = o.notesDir || "";
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
                direction: o.direction || "auto",
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
            if (notes.dir) notes.load();

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
        case "direction": win.direction = value; if (!initial) Qt.callLater(win.relayout); break;
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
    // must match FILL in align.js — a .pragma library's plain vars don't
    // reach QML (only its functions do), so Align.FILL reads as undefined.
    // Private-use, because TextEdit turns a non-breaking space back into a
    // plain one the moment it's typed, which silently erased every skip
    readonly property string fill: ""

    // A cluster is a character plus whatever rides on it (the second half of
    // an emoji, Hebrew vowel points, accents): one cell, or two for wide
    // characters, drawn as a single glyph.
    function glyphAt(s, i) {
        if (!Bidi.width(s, i)) return "";
        var ch = s[i];
        if (ch === "\n" || ch === "\t" || ch === " " || ch === win.fill) return "";
        var e = i + 1;
        while (e < s.length && s[e] !== "\n" && !Bidi.width(s, e)) e++;
        return s.substring(i, e);
    }
    function mirrorIf(g, odd) { return g.length === 1 ? Bidi.mirror(g, odd) : g; }

    // which way a paragraph runs: code always left to right; WRITE and NOTES
    // follow the setting; everything else goes by its first strong letter
    function paraBase(text, prev) {
        if (win.mode === "code") return 0;
        if (win.mode === "write" || win.mode === "notes") {
            if (win.direction === "ltr") return 0;
            if (win.direction === "rtl") return 1;
        }
        var b = Bidi.strong(text);
        return b < 0 ? prev : b;
    }

    // WRITE and NOTES wrap words (spaces hang off the end of a line, a word
    // that won't fit hops down whole); everything else keeps its lines as they
    // are and the page scrolls sideways instead.
    function wrapRows(s, W, a, b, C) {
        var out = [], rowStart = a, col = 0, i = a;
        while (i < b) {
            if (s[i] === " " || s[i] === "\t") { col += W[i]; i++; continue; }
            var j = i, w = 0;
            while (j < b && s[j] !== " " && s[j] !== "\t") { w += W[j]; j++; }
            if (col > 0 && col + w > C) { out.push([rowStart, i]); rowStart = i; col = 0; }
            for (var k = i; k < j; k++) {       // a word longer than the line breaks where it must
                if (W[k] && col > 0 && col + W[k] > C) { out.push([rowStart, k]); rowStart = k; col = 0; }
                col += W[k];
            }
            i = j;
        }
        out.push([rowStart, b]);
        return out;
    }

    // puts one row's characters on the grid, in bidi order
    function placeRow(s, W, a, b, row, base, C, L, para) {
        var k;
        if (win.slotMode) {
            // slot typing sits exactly on its ghost letter
            var gv = para < win.ghostVis.length ? win.ghostVis[para] : null;
            for (k = a; k < b; k++) {
                var j = k - a, inG = gv && j < gv.col.length;
                L.c[k] = inG ? gv.col[j] : (gv ? gv.after + (j - gv.col.length) : j);
                L.odd[k] = inG ? gv.odd[j] : false;
                L.g[k] = mirrorIf(glyphAt(s, k), L.odd[k]);
                L.f[k] = Bidi.kind(s[k]) === "R";
                L.cc[k] = gv ? (j < gv.caret.length ? gv.caret[j] : gv.after) : j;
                L.cr[k] = row;
            }
            return;
        }
        var cells = [], ids = [];
        for (k = a; k < b; k++) if (W[k]) { cells.push(glyphAt(s, k) || s[k]); ids.push(k); }
        var res = Bidi.layout(cells, base), x = 0, xs = new Array(cells.length), coreRight = 0;
        for (var v = 0; v < res.order.length; v++) {
            var li = res.order[v];
            xs[li] = x;
            x += W[ids[li]];
            if (!/^[\s]$/.test(cells[li])) coreRight = x;
        }
        // a right-to-left row hangs from the right edge
        var shift = base ? C - coreRight : 0;
        for (var n = 0; n < cells.length; n++) {
            k = ids[n];
            var col = xs[n] + shift;
            // only wrapped text clamps (its trailing spaces hang at the edge); a
            // line that doesn't wrap just carries on, and the page scrolls to it
            L.c[k] = win.nowrap ? col : (base ? Math.max(0, col) : Math.min(col, C));
            L.odd[k] = (res.level[n] & 1) === 1;
            L.g[k] = mirrorIf(glyphAt(s, k), L.odd[k]);
            L.f[k] = Bidi.kind(s[k]) === "R";
        }
        var last = -1;
        for (k = a; k < b; k++) {
            if (W[k]) { last = k; continue; }
            L.c[k] = last >= 0 ? L.c[last] : (base ? C : 0);      // rides on its cluster
            L.odd[k] = last >= 0 ? L.odd[last] : base === 1;
            L.g[k] = ""; L.f[k] = false;
        }
        // the caret before a character: its right edge when it runs right to left
        for (k = a; k < b; k++) {
            var bk = k;
            while (bk > a && !W[bk]) bk--;
            L.cc[k] = L.odd[bk] ? L.c[bk] + W[bk] : L.c[bk];
            L.cr[k] = row;
        }
    }

    // where the caret goes after a row's last character
    function afterRow(a, b, base, C, L, W, para) {
        if (win.slotMode) return slotCaret(para, b - a);
        var k = b - 1;
        while (k >= a && !W[k]) k--;
        if (k < a) return base ? C : 0;
        return L.odd[k] ? L.c[k] : L.c[k] + W[k];
    }
    function slotCaret(para, j) {
        var gv = para < win.ghostVis.length ? win.ghostVis[para] : null;
        if (!gv) return j;
        return j < gv.caret.length ? gv.caret[j] : gv.after;
    }

    function layout(s) {
        var n = s.length, C = win.slotMode ? win.longest : win.cols, wrap = !win.nowrap;
        var W = new Array(n), i;
        for (i = 0; i < n; i++) W[i] = s[i] === "\n" ? 0 : Bidi.width(s, i);
        var L = { c: new Array(n), r: new Array(n), g: new Array(n), f: new Array(n), odd: new Array(n),
                  cc: new Array(n + 1), cr: new Array(n + 1) };
        var row = 0, start = 0, para = 0;
        var prevBase = (win.mode === "write" || win.mode === "notes") && win.direction === "rtl" ? 1 : 0;
        while (true) {
            var nl = s.indexOf("\n", start);
            if (nl < 0) nl = n;
            var base = paraBase(s.substring(start, nl), prevBase);
            prevBase = base;
            var rows = wrap && !win.slotMode ? wrapRows(s, W, start, nl, C) : [[start, nl]];
            for (var q = 0; q < rows.length; q++) {
                placeRow(s, W, rows[q][0], rows[q][1], row, base, C, L, para);
                for (i = rows[q][0]; i < rows[q][1]; i++) L.r[i] = row;
                if (q === rows.length - 1) {
                    L.cc[nl] = afterRow(rows[q][0], rows[q][1], base, C, L, W, para);
                    L.cr[nl] = row;
                    if (nl < n) {
                        L.c[nl] = Math.max(0, Math.min(L.cc[nl], C));
                        L.r[nl] = row; L.g[nl] = ""; L.f[nl] = false; L.odd[nl] = false;
                    }
                }
                row++;
            }
            if (nl >= n) break;
            start = nl + 1;
            para++;
            if (start === n) {                   // ends in a newline: an empty last line
                var eb = paraBase("", prevBase);
                L.cc[n] = win.slotMode ? slotCaret(para, 0) : (eb ? C : 0);
                L.cr[n] = row;
                break;
            }
        }
        L.w = W;
        L.ec = L.cc[n];
        L.er = L.cr[n];
        return L;
    }

    // ── the ghost ───────────────────────────────────────────────────────────
    // Each ghost letter is its own item too, placed by the same bidi rules as
    // the typing, so a Hebrew lyric or a Hebrew comment sits where your
    // letters will land.
    function ghostLine(g, base) {
        var n = g.length, W = new Array(n), k;
        for (k = 0; k < n; k++) W[k] = Bidi.width(g, k);
        var cells = [], ids = [];
        for (k = 0; k < n; k++) if (W[k]) { cells.push(glyphAt(g, k) || g[k]); ids.push(k); }
        var res = Bidi.layout(cells, base), x = 0, xs = new Array(cells.length);
        for (var v = 0; v < res.order.length; v++) { xs[res.order[v]] = x; x += W[ids[res.order[v]]]; }
        return { n: n, W: W, ids: ids, xs: xs, level: res.level, total: x, base: base };
    }
    function finishGhostLine(raw, C) {
        var n = raw.n, col = new Array(n), odd = new Array(n), caret = new Array(n + 1), k;
        var shift = raw.base ? C - raw.total : 0;
        for (var i = 0; i < raw.ids.length; i++) {
            k = raw.ids[i];
            col[k] = raw.xs[i] + shift;
            odd[k] = (raw.level[i] & 1) === 1;
        }
        var last = -1;
        for (k = 0; k < n; k++) {
            if (raw.W[k]) { last = k; continue; }
            col[k] = last >= 0 ? col[last] : (raw.base ? C : 0);
            odd[k] = last >= 0 ? odd[last] : raw.base === 1;
        }
        for (k = 0; k < n; k++) {
            var bk = k;
            while (bk > 0 && !raw.W[bk]) bk--;
            caret[k] = odd[bk] ? col[bk] + raw.W[bk] : col[bk];
        }
        var lk = n - 1;
        while (lk >= 0 && !raw.W[lk]) lk--;
        var after = lk < 0 ? (raw.base ? C : 0) : (odd[lk] ? col[lk] : col[lk] + raw.W[lk]);
        caret[n] = after;
        return { col: col, odd: odd, caret: caret, after: after, W: raw.W };
    }
    function buildGhost() {
        var raws = [], widest = 0, prev = 0;
        for (var r = 0; r < win.ghostLines.length; r++) {
            var g = win.ghostLines[r];
            var base = win.mode === "code" ? 0 : Bidi.strong(g);
            if (base < 0) base = prev;
            prev = base;
            var raw = ghostLine(g, base);
            raws.push(raw);
            widest = Math.max(widest, raw.total);
        }
        win.ghostVis = raws.map(function(raw) { return finishGhostLine(raw, widest); });
        win.ghostCells = widest;
        buildGhostModel();
    }

    property var ghostItem: []     // per row: unit index → model index (-1: nothing drawn)
    property var gShown: []
    property var gMissed: []
    function buildGhostModel() {
        ghostModel.clear();
        var rows = [], shown = [], missed = [], items = [];
        for (var r = 0; r < win.ghostLines.length; r++) {
            var g = win.ghostLines[r], gv = win.ghostVis[r], map = [];
            for (var k = 0; k < g.length; k++) {
                map.push(-1);
                var gl = glyphAt(g, k);
                if (!gl) continue;
                map[k] = items.length;
                items.push({ row: r, col: gv.col[k], ch: mirrorIf(gl, gv.odd[k]), cw: gv.W[k],
                             rf: Bidi.kind(g[k]) === "R", shown: true, missed: false });
                shown.push(true);
                missed.push(false);
            }
            rows.push(map);
        }
        if (items.length) ghostModel.append(items);
        win.ghostItem = rows;
        win.gShown = shown;
        win.gMissed = missed;
    }
    function updateGhost(view) {
        var shown = win.gShown, missed = win.gMissed;
        for (var r = 0; r < win.ghostItem.length; r++) {
            var map = win.ghostItem[r], v = view && r < view.length ? view[r] : null;
            var mask = v ? v.text : win.ghostLines[r], miss = v ? (v.missed || "") : "";
            for (var k = 0; k < map.length; k++) {
                var mi = map[k];
                if (mi < 0) continue;
                var s1 = k < mask.length && mask[k] !== " ";
                var m1 = k < miss.length && miss[k] !== " ";
                if (shown[mi] !== s1) { shown[mi] = s1; ghostModel.setProperty(mi, "shown", s1); }
                if (missed[mi] !== m1) { missed[mi] = m1; ghostModel.setProperty(mi, "missed", m1); }
            }
        }
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
        if (win.ghostItem.length) updateGhost(al ? al.view : null);
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
        var move = function(idx, oi) {
            var nb = bad ? bad[idx] : false;
            if (win.pc[oi] !== L.c[idx]) charModel.setProperty(idx, "px", L.c[idx]);
            if (win.pr[oi] !== L.r[idx]) charModel.setProperty(idx, "py", L.r[idx]);
            if (win.pg[oi] !== L.g[idx]) charModel.setProperty(idx, "g", L.g[idx]);
            if (win.pw[oi] !== L.w[idx]) charModel.setProperty(idx, "cw", Math.max(1, L.w[idx]));
            if (win.pf[oi] !== L.f[idx]) charModel.setProperty(idx, "rf", L.f[idx]);
            if (!!win.badArr[oi] !== nb) charModel.setProperty(idx, "bad", nb);
        };
        for (i = 0; i < p; i++) move(i, i);

        // a paste, a restored page or a mode switch sweeps in as a wave; a
        // keystroke lands immediately
        var span = ins > 1 ? Math.min(1400, ins * 9) : 0;
        var rows = [];
        for (i = 0; i < ins; i++) {
            var at = p + i;
            rows.push({ g: L.g[at], px: L.c[at], py: L.r[at], cw: Math.max(1, L.w[at]), rf: L.f[at],
                        bad: bad ? bad[at] : false, born: ins > 1 ? Math.round(i / ins * span) : 0 });
        }
        if (p === charModel.count) charModel.append(rows);
        else for (i = 0; i < rows.length; i++) charModel.insert(p + i, rows[i]);

        for (i = p + ins; i < nn; i++) move(i, i - ins + del);

        win.units = s.split("");
        win.pc = L.c; win.pr = L.r; win.pg = L.g; win.pw = L.w; win.pf = L.f;
        win.cc = L.cc; win.cr = L.cr;
        win.badArr = bad || [];
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

    // everything re-placed (window resized, letters resized, direction changed)
    function relayout() {
        var s = ed.text, L = layout(s);
        for (var i = 0; i < s.length; i++) {
            if (win.pc[i] !== L.c[i]) charModel.setProperty(i, "px", L.c[i]);
            if (win.pr[i] !== L.r[i]) charModel.setProperty(i, "py", L.r[i]);
            if (win.pg[i] !== L.g[i]) charModel.setProperty(i, "g", L.g[i]);
            if (win.pf[i] !== L.f[i]) charModel.setProperty(i, "rf", L.f[i]);
        }
        win.pc = L.c; win.pr = L.r; win.pg = L.g; win.pw = L.w; win.pf = L.f;
        win.cc = L.cc; win.cr = L.cr;
        win.endCol = L.ec; win.endRow = L.er;
        realign();
        updateCaret();
        updateSelection();
    }
    onColsChanged: Qt.callLater(win.relayout)

    function center(i) {
        var c = i < win.pc.length ? win.pc[i] : win.endCol, r = i < win.pr.length ? win.pr[i] : win.endRow;
        var w = i < win.pw.length ? Math.max(1, win.pw[i]) : 1;
        return { x: win.padX + c * win.slot + (win.charW * w) / 2, y: r * win.lineH + win.lineH / 2 };
    }

    // deleted letters get a stand-in that plays the exit where they stood —
    // only the ones on screen, so clearing a long page stays cheap
    function ghostOut(from, count) {
        var made = 0;
        for (var i = from; i < from + count && made < 400; i++) {
            var it = rep.itemAt(i);
            if (!it || it.glyph === "" || !win.near(win.pr[i])) continue;
            win.ghostComp.createObject(content, {
                w: win, style: win.exit, glyph: it.glyph, x: it.x, y: it.y, width: it.width,
                rise: it.rise + it.bump, scale: it.scale, rotation: it.rotation, color: it.color
            });
            if (win.exit === "dust" && made < 40) sparkAt(it.x + it.width / 2, it.y + win.lineH / 2 + it.rise, 6);
            made++;
        }
    }

    function updateCaret() {
        var k = Math.min(ed.cursorPosition, win.units.length);
        if (k < win.cc.length && win.cc[k] !== undefined) { win.caretCol = win.cc[k]; win.caretRow = win.cr[k]; }
        else { win.caretCol = win.endCol; win.caretRow = win.endRow; }
        caret.opacity = 1;
        blink.restart();
        follow();
    }

    function updateSelection() {
        var a = Math.min(ed.selectionStart, ed.selectionEnd), b = Math.max(ed.selectionStart, ed.selectionEnd);
        var segs = [], byRow = {};
        for (var i = a; i < b && i < win.units.length; i++) {
            if (win.units[i] === "\n" || !win.pw[i]) continue;
            var r = win.pr[i], c0 = win.pc[i], c1 = c0 + win.pw[i];
            if (!byRow[r]) { byRow[r] = { row: r, c0: c0, c1: c1 }; segs.push(byRow[r]); }
            else { byRow[r].c0 = Math.min(byRow[r].c0, c0); byRow[r].c1 = Math.max(byRow[r].c1, c1); }
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

    // the text position whose caret spot is nearest a click
    function indexAt(px, py) {
        var row = Math.floor(py / win.lineH), col = (px - win.padX) / win.slot;
        var n = win.units.length, best = n, bestD = 1e9;
        for (var k = 0; k <= n; k++) {
            if (win.cr[k] !== row) continue;
            var d = Math.abs(win.cc[k] - col);
            if (d < bestD) { bestD = d; best = k; }
        }
        if (bestD === 1e9 && row < win.endRow)
            for (k = 0; k <= n; k++) if (win.cr[k] > row) return Math.max(0, k - 1);
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
        if (win.strict && win.ghosted && atEnd) {
            var want = Align.expected(Align.state(ed.text, win.ghostLines));
            if (want && t !== want && !(t === " " && want === "\n")) {
                sfxObj.play("error");
                shakePage(2.5);
                caretShake.restart();
                return true;
            }
        }

        // CODE with no ghost: a closing brace on an empty indented line steps
        // back out one level, like any editor
        if (win.mode === "code" && !win.ghosted && t === "}" && win.codeLang !== "python") {
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
        if (win.mode === "notes") notes.changed(ed.text);
        if (win.mode === "lyrics") songAlive();
        if (win.mode === "speed") {
            if (ch.ins >= 1) speed.onKey(kind);
            if (win.ghostLines.length - win.endRow < 4) extendSpeed();
        }
        checkComplete();
    }

    // CODE: Enter lands on the next line already indented — like the ghost
    // when there is one, otherwise like the line above, one deeper after a
    // line that opens a block
    function autoIndent() {
        var i = ed.cursorPosition, s = ed.text;
        var before = s.substr(0, i).split("\n"), row = before.length - 1, pad = "";
        if (win.ghosted && row < win.ghostLines.length) {
            var g = win.ghostLines[row];
            pad = g.substr(0, g.length - g.replace(/^\s+/, "").length);
        } else if (!win.ghosted) {
            var prev = row > 0 ? before[row - 1] : "";
            pad = prev.substr(0, prev.length - prev.replace(/^\s+/, "").length);
            if (win.codeLang === "python") { if (/:\s*(#.*)?$/.test(prev)) pad += "    "; }
            else if (/[{\[(]\s*$/.test(prev) || (win.codeLang === "bash" && /\b(then|do|else)\s*$/.test(prev))) pad += "  ";
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

    // CODE: does what you've written run? (said in the header, quietly)
    Timer {
        id: compileCheck
        interval: 450
        onTriggered: {
            var code = ed.text;
            if (!code.trim().length || win.mode !== "code") { win.compileState = null; return; }
            if (win.codeLang === "js") { win.compileState = stage.check(code); return; }
            win.ask({ action: "check", lang: win.codeLang, code: code }, function(r) {
                if (ed.text !== code) return;
                win.compileState = r.ok ? { ok: true } : { ok: false, message: r.message || r.error || "", line: r.line || -1 };
            });
        }
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
    // The old letters are cleared BEFORE the ghost changes: a new ghost can
    // resize the font, and letters leaving afterwards played their exit in
    // the new size at the old spacing.
    function setGhost(t) {
        win.target = t;
        win.ghostLines = t.length ? t.split("\n") : [];
        buildGhost();
    }
    function startPiece(t) {
        setText("");
        setGhost(t);
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
        setGhost(win.target + "\n" + more.join("\n"));
        realign();
    }
    function cycleSpeed(key, list, d) {
        var cur = key === "speed_time" ? win.speedTime : win.speedText;
        var i = list.indexOf(cur);
        setSetting(key, list[(i + d + list.length) % list.length]);
    }

    // whatever the mode being left needs to keep
    function leaveMode(next) {
        if (win.mode === "write") win.writeText = ed.text;
        if (win.mode === "notes") notes.flush();
        if (win.mode === "lyrics" && next !== "lyrics") songStop();
    }

    function setMode(m) {
        if (m === win.mode && (m === "write" || m === "notes")) return;
        if (m === "write") {
            leaveMode(m);
            setText("");
            win.mode = "write";
            setGhost("");
            win.pieceName = "";
            setText(win.writeText);
            Qt.callLater(win.relayout);
        } else if (m === "notes") {
            leaveMode(m);
            setText("");
            win.mode = "notes";
            setGhost("");
            win.pieceName = "";
            if (notes.ready) enterNotes(); else notes.load(enterNotes);
        } else if (m === "speed") {
            leaveMode(m);
            win.mode = "speed";
            win.pieceName = "";
            startSpeed();
        } else if (m === "code") {
            var blank = ["js", "python", "bash"].map(function(l) {
                return { title: "✎ blank page — " + win.langNames[l], sub: "write your own · ctrl+enter runs whatever you wrote",
                         tag: l, blank: true, lang: l };
            });
            picker.open("CODE — pick something to type, or start blank", blank.concat(win.snippetList.map(function(s) {
                return { title: s.name, sub: s.about, tag: s.lang + " · " + s.level, snippet: s };
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
                    "nothing is playing and your music folder is empty. Play a song in Spotify, YouTube or mpv, then press F4 again — or drop audio files into ~/.local/share/bite-os/bitewrite/songs");
            });
        }
    }

    function pickerChosen(item) {
        if (picker.purpose === "notes") { openNote(item.id); ed.forceActiveFocus(); return; }
        leaveMode(picker.purpose);
        if (picker.purpose === "code") {
            win.mode = "code";
            if (item.blank) {
                win.codeLang = item.lang;
                win.pieceName = "blank page";
                startPiece("");
                toast("write anything in " + win.langNames[item.lang] + " — ctrl+enter runs it"
                      + (item.lang === "js" ? " (define function frame(t) and draw with ctx)" : " in " + (win.terminalName || "a terminal")));
            } else {
                win.codeLang = item.snippet.lang;
                win.pieceName = item.snippet.name;
                startPiece(item.snippet.code);
                toast("type it over the ghost, or ctrl+f to finish it and edit — ctrl+enter runs whatever you wrote");
            }
        } else {
            win.mode = "lyrics";
            openLyrics(item.song);
        }
        ed.forceActiveFocus();
    }

    // CODE: fill in the rest of the ghost and hand the program over to edit
    function finishCode() {
        if (win.mode !== "code" || !win.ghosted) return;
        var t = win.target;
        setText(t);
        setGhost("");
        Qt.callLater(win.relayout);
        win.complete = true;
        compileCheck.restart();
        sfxObj.play("done");
        celebrate();
        toast("finished — it's all yours to change · ctrl+enter runs it");
    }

    // runs exactly what's on the page: broken code doesn't run, valid code does
    function runCode() {
        var code = ed.text;
        if (!code.trim().length) { toast("nothing to run yet"); sfxObj.play("error"); return; }
        if (win.codeLang === "js") {
            var c = stage.check(code);
            if (!c.ok) { brokenCode(c); return; }
            sfxObj.play("run");
            stage.run(code);
            return;
        }
        ask({ action: "check", lang: win.codeLang, code: code }, function(r) {
            if (!r.ok) { brokenCode(r); return; }
            sfxObj.play("run");
            ask({ action: "run", lang: win.codeLang, code: code }, function(x) {
                toast(x.ok ? "running in " + x.terminal + " — close it when you're done" : (x.error || "couldn't start a terminal"));
            });
        });
    }
    function brokenCode(c) {
        toast("it doesn't run — " + (c.line > 0 ? "line " + c.line + ": " : "") + (c.message || c.error || "")
              + (win.codeLang === "js" && !(c.line > 0) ? " · check brackets, quotes and commas" : ""));
        sfxObj.play("error");
        shakePage(4);
    }

    // ── notes ───────────────────────────────────────────────────────────────
    function enterNotes() {
        if (!notes.notes.length) { newNote(); return; }
        var id = notes.current && notes.titleFor(notes.current) !== "" ? notes.current : notes.notes[0].id;
        openNote(id);
    }
    function openNote(id) {
        if (win.mode !== "notes") return;
        notes.open(id, function(txt) {
            if (win.mode !== "notes" || notes.current !== id) return;
            setText(txt);
            Qt.callLater(win.relayout);
        });
    }
    function newNote() {
        notes.create();
        setText("");
        toast("a new note — its first line is its title");
        ed.forceActiveFocus();
    }
    function deleteNote(id) {
        var title = notes.titleFor(id);
        var was = id === notes.current;
        var next = was ? (notes.neighbor(1) || notes.neighbor(-1)) : "";
        notes.remove(id);
        ask({ action: "delete_note", id: id }, null);
        toast("deleted “" + title + "”");
        if (!was) return;
        notes.current = "";
        if (next) openNote(next); else newNote();
    }
    property string deleteArmed: ""
    Timer { id: deleteDisarm; interval: 2500; onTriggered: win.deleteArmed = "" }
    function deleteCurrentNote() {
        var id = notes.current;
        if (!id) return;
        if (win.deleteArmed === id) { win.deleteArmed = ""; deleteNote(id); return; }
        win.deleteArmed = id;
        deleteDisarm.restart();
        toast("press it again to delete “" + notes.titleFor(id) + "”");
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
        notes.flush();
        var page = win.mode === "write" ? ed.text : win.writeText;
        ask({ action: "quit" }, null);
        if (win.keep && win.draftPath) {
            win.writeFile(win.draftPath, page, function() { Qt.quit(); });
            quitGuard.start();
        } else {
            quitGuard.interval = 300; quitGuard.start();
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
        var ext = win.mode !== "code" ? ".txt" : win.codeLang === "python" ? ".py" : win.codeLang === "bash" ? ".sh" : ".js";
        var name = "bitewrite-" + d.getFullYear() + "-" + z(d.getMonth() + 1) + "-" + z(d.getDate()) + "-" +
                   z(d.getHours()) + z(d.getMinutes()) + z(d.getSeconds()) + ext;
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
            var ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
            if (panel.handle(e)) { e.accepted = true; return; }
            var times = ["15", "30", "60", "120", "infinite", "custom"], texts = ["words", "sentences", "hard", "page"];
            var fkey = e.key >= Qt.Key_F1 && e.key <= Qt.Key_F6;

            // a finished SPEED run: the card is up and the page is locked
            if (win.mode === "speed" && speed.finished && !ctrl && !fkey) {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.startSpeed();
                else if (e.key === Qt.Key_Tab) win.cycleSpeed("speed_time", times, 1);
                else if (e.key === Qt.Key_Backtab) win.cycleSpeed("speed_text", texts, 1);
                else if (e.key === Qt.Key_Escape) win.setMode("write");
                e.accepted = true;
                return;
            }

            if (e.key === Qt.Key_F1) win.setMode("write");
            else if (e.key === Qt.Key_F2) win.setMode("notes");
            else if (e.key === Qt.Key_F3) win.setMode("code");
            else if (e.key === Qt.Key_F4) win.setMode("lyrics");
            else if (e.key === Qt.Key_F5) win.setMode("speed");
            else if (e.key === Qt.Key_F6 || (ctrl && e.key === Qt.Key_Comma)) panel.open();
            else if (ctrl && e.key === Qt.Key_Q) win.leave();
            else if (e.key === Qt.Key_Escape) { if (win.mode !== "write") win.setMode("write"); else win.leave(); }
            else if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                if (win.mode === "code") win.runCode();
                else if (win.mode === "lyrics") { if (win.songPlaying) win.songPause(); else { win.followWait = false; win.songPlay(); } }
            }
            else if (ctrl && e.key === Qt.Key_F && win.mode === "code") win.finishCode();
            else if (ctrl && e.key === Qt.Key_R) {
                if (win.mode === "speed") win.startSpeed();
                else if (win.ghosted) win.startPiece(win.target);
            }
            else if (ctrl && e.key === Qt.Key_N) {
                if (win.mode === "speed") win.startSpeed();
                else if (win.mode === "notes") win.newNote();
                else if (win.mode !== "write") win.setMode(win.mode);
            }
            else if (ctrl && e.key === Qt.Key_K && win.mode === "notes") {
                picker.open("NOTES — find a note", notes.notes.map(function(n) {
                    return { title: n.title, sub: notes.ago(n.updated), tag: n.id === notes.current ? "open" : "", id: n.id };
                }), "no notes yet");
                picker.purpose = "notes";
            }
            else if (alt && (e.key === Qt.Key_Up || e.key === Qt.Key_Down) && win.mode === "notes") {
                var nb = notes.neighbor(e.key === Qt.Key_Up ? -1 : 1);
                if (nb) win.openNote(nb);
            }
            else if (ctrl && shift && (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && win.mode === "notes") win.deleteCurrentNote();
            else if (ctrl && e.key === Qt.Key_H) win.ghostHidden = !win.ghostHidden;
            else if (ctrl && e.key === Qt.Key_S) win.saveCopy();
            else if (ctrl && e.key === Qt.Key_L) { if (ed.length) ed.remove(0, ed.length); }
            else if (ctrl && (e.key === Qt.Key_Equal || e.key === Qt.Key_Plus)) win.userPx = Math.min(72, win.userPx + 2);
            else if (ctrl && e.key === Qt.Key_Minus) win.userPx = Math.max(12, win.userPx - 2);
            else if (ctrl && e.key === Qt.Key_M) { sfxObj.muted = !sfxObj.muted; win.toast(sfxObj.muted ? "sound off" : "sound on"); }
            else if (e.key === Qt.Key_Backtab) { if (win.mode === "speed") win.cycleSpeed("speed_text", texts, 1); }
            else if (e.key === Qt.Key_Tab) {
                if (win.mode === "speed") win.cycleSpeed("speed_time", times, 1);
                else if (win.mode !== "lyrics") ed.insert(ed.cursorPosition, win.mode !== "code" ? "    " : win.codeLang === "python" ? "    " : "  ");
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
            model: ["write", "notes", "code", "lyrics", "speed"]
            delegate: Text {
                readonly property bool on: win.mode === modelData
                text: modelData.toUpperCase()
                font.family: win.fontFamily
                font.pixelSize: 13
                font.letterSpacing: 2
                color: on ? win.cAccent : win.cSub
                opacity: on ? 1 : 0.55
                Behavior on color { ColorAnimation { duration: 160 } }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.setMode(modelData) }
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
        width: Math.max(0, parent.width - 2 * Math.max(tabs.width, counts.width + finishBtn.width + 20) - 120)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: win.mode !== "speed"
        text: win.mode === "notes" ? notes.titleFor(notes.current)
            : win.mode === "code" ? (win.pieceName ? win.pieceName + "   ·   " : "") + win.langNames[win.codeLang]
            : win.pieceName + (win.mode === "lyrics" && win.song
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
              + (win.compileState === null ? "" : win.compileState.ok ? "✓ runs"
                 : "✗ doesn't run" + (win.compileState.line > 0 ? " (line " + win.compileState.line + ")" : ""))
            : win.ghosted
            ? Math.min(ed.length, win.target.length) + " / " + win.target.length + (win.wrong ? "   ·   " + win.wrong + " wrong" : "")
            : counts.words + (counts.words === 1 ? " word" : " words") + "   ·   " + (win.endRow + 1) + (win.endRow === 0 ? " line" : " lines")
              + (win.mode === "notes" ? "   ·   " + notes.notes.length + (notes.notes.length === 1 ? " note" : " notes") : "")
        anchors.right: parent.right
        anchors.bottom: page.top
        anchors.bottomMargin: 12
        anchors.rightMargin: 28
        font.family: win.fontFamily
        font.pixelSize: 13
        color: counts.broken || (win.mode !== "code" && win.wrong) ? win.cBad : win.cSub
        opacity: 0.75
    }

    // CODE: skip the typing and go straight to changing the result
    Rectangle {
        id: finishBtn
        visible: win.mode === "code" && win.ghosted
        anchors.right: counts.left
        anchors.rightMargin: 16
        anchors.verticalCenter: counts.verticalCenter
        width: visible ? finishLabel.implicitWidth + 20 : 0
        height: 24
        radius: 12
        color: finishHover.hovered ? Qt.alpha(win.cAccent, 0.2) : "transparent"
        border.width: 1
        border.color: Qt.alpha(win.cAccent, 0.45)
        Text {
            id: finishLabel
            anchors.centerIn: parent
            text: "⏭ finish code"
            font.family: win.fontFamily
            font.pixelSize: 12
            color: win.cAccent
        }
        HoverHandler { id: finishHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { win.finishCode(); ed.forceActiveFocus(); } }
    }

    Rectangle {
        id: page
        readonly property real comboHeat: win.comboOn ? Math.min(1, win.combo / 60) : 0
        width: Math.min(win.cols * win.slot + 2 * win.padX, win.width - 40 - win.sideRoom)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: win.sideRoom / 2
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
        Behavior on anchors.horizontalCenterOffset { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

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
                    text: win.mode === "code" ? (win.codeLang === "js" ? "write some code — define function frame(t) and draw with ctx"
                                                                      : "write some " + win.langNames[win.codeLang] + " — ctrl+enter runs it")
                        : win.mode === "notes" ? "a new note — the first line is its title"
                        : "just write."
                    x: win.padX
                    height: win.lineH
                    verticalAlignment: Text.AlignVCenter
                    font.family: win.fontFamily
                    font.pixelSize: win.fontPx
                    color: win.cSub
                    opacity: win.ready && charModel.count === 0 && !win.ghosted ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }

                // the ghost: one item per letter, placed like the typing
                Repeater {
                    model: ghostModel
                    delegate: Text {
                        readonly property bool sung: win.sungRow >= 0 && model.row >= win.sungRow && model.row <= win.sungRowEnd
                        x: win.padX + model.col * win.slot
                        y: model.row * win.lineH
                        width: win.charW * model.cw + (model.cw - 1)
                        height: win.lineH
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: model.ch
                        font.family: model.rf && win.fontRtl ? win.fontRtl : win.fontFamily
                        font.pixelSize: win.fontPx
                        // letters skipped with a space stay in their place, in red
                        color: model.missed ? win.cBad : (sung ? win.cAccent : win.cText)
                        opacity: win.ghostHidden || !(model.shown || model.missed) ? 0
                               : model.missed ? 0.6
                               : win.mode === "speed" ? 0.5
                               : (sung ? Math.max(0.55, win.ghostLevel / 10) : win.ghostLevel / 10 * 0.6)
                        Behavior on opacity { NumberAnimation { duration: 120 } }
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
                        cells: model.cw
                        rtlFont: model.rf
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
            // U+200E: "×34" has no letters to say which way it reads, and under a
            // Hebrew locale Qt flipped it to "34×"
            text: "\u200e×" + win.combo
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
            ? "ctrl+enter run   ·   ctrl+f finish   ·   ctrl+n another   ·   ctrl+r restart   ·   ctrl+h hide ghost   ·   f6 settings   ·   esc back"
            : win.mode === "lyrics"
            ? "ctrl+enter play / pause   ·   ctrl+n another song   ·   ctrl+r restart   ·   f6 settings   ·   esc back"
            : win.mode === "notes"
            ? "ctrl+n new note   ·   ctrl+k find   ·   alt+↑↓ switch   ·   ctrl+shift+del delete   ·   f6 settings   ·   esc back"
            : "f2 notes   ·   f3 code   ·   f4 lyrics   ·   f5 speed   ·   f6 settings   ·   ctrl+s save   ·   esc close"
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
    Notes {
        id: notes
        w: win
        page: page
    }

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
