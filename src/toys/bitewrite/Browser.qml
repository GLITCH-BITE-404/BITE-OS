// Shows the HTML you typed the way a browser would — except there is no
// browser. The chrome is drawn here (a strip of tabs, back/forward, the
// address bar, the loading sweep, a status line that names the link under your
// mouse) and each page is Qt's rich-text engine, which reads a real subset of
// HTML and CSS. So this is a small, honest browser: headings, paragraphs,
// lists, tables, links, images, colours, fonts and backgrounds all land.
// Scripts, canvas, video, forms, flexbox and grid do not — and instead of
// quietly dropping them, the status line counts them out loud.
//
// It holds as many pages open at once as you like. Ctrl+Enter sends the page
// you are writing to a new tab, so the last five things you tried are all
// still there to flip between. Ctrl+T opens the start page, which lists every
// page this machine has — what you typed, and each of the pages in snippets/ —
// and a link from one to another really does go there, with its own history
// per tab, so ‹ and › mean something.
//
// Nothing here executes: no network, no JavaScript, no file it wasn't given.
// A link to the outside world lands on an offline page, and a link to a file
// that isn't here lands on a not-found page — both written on the spot, the
// way a browser writes its own error pages.

import QtQuick
import QtQuick.Window

Item {
    id: browser
    property var w
    property bool running: false

    // Each tab: { url, raw, body, title, bg, ink, family, elements, missing,
    //             zoom, scrollY, hist: [{url, raw}], hpos }
    property var tabs: []
    property int current: -1
    readonly property var tab: browser.current >= 0 && browser.current < browser.tabs.length
                               ? browser.tabs[browser.current] : null

    // every page this little machine has: { file, title, about, raw }
    property var site: []
    property string hovered: ""
    property real loaded: 0            // 0 → 1, the sweep in the address bar
    signal stopped()

    visible: opacity > 0
    opacity: running ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property string root: "file://" + (w && w.homeDir ? w.homeDir : "") +
                                   "/.local/share/bite-os/bitewrite/run/"
    readonly property string ownFile: "your-page.html"

    // ── fonts ───────────────────────────────────────────────────────────────

    readonly property var families: ({
        serif: ["Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "Georgia"],
        "sans-serif": ["Helvetica", "Liberation Sans", "DejaVu Sans", "Noto Sans", "Arial"],
        monospace: ["JetBrainsMono Nerd Font", "JetBrains Mono", "Liberation Mono", "DejaVu Sans Mono", "Noto Sans Mono"],
        cursive: ["Comic Neue", "URW Chancery L", "DejaVu Serif"]
    })
    function firstFamily(list) {
        var have = Qt.fontFamilies();
        for (var i = 0; i < list.length; i++) if (have.indexOf(list[i]) >= 0) return list[i];
        return "";
    }
    // a browser's default page font is a serif — whichever of these exists
    readonly property string pageFont: firstFamily(browser.families.serif) || (w ? w.fontFamily : "")

    // font-family: "Some Face", monospace — the first name this machine has,
    // and the generic ones mean what they mean everywhere else
    function familyOf(v) {
        if (!v) return "";
        var names = v.split(",");
        for (var i = 0; i < names.length; i++) {
            var n = names[i].trim().replace(/^["']|["']$/g, "");
            if (!n) continue;
            if (browser.families[n.toLowerCase()]) {
                var g = firstFamily(browser.families[n.toLowerCase()]);
                if (g) return g;
                continue;
            }
            if (Qt.fontFamilies().indexOf(n) >= 0) return n;
        }
        return "";
    }

    // ── reading a page ──────────────────────────────────────────────────────

    function pick(re, s) { var m = re.exec(s); return m ? m[1] : ""; }

    // <style> rules and a style="" attribute both say it; the attribute wins,
    // and the last rule of the same kind wins over the ones before it, which
    // is close enough to how a browser settles this.
    function cssOf(html, selector, prop) {
        var out = "";
        var rules = new RegExp("(?:^|[},;>\\s])" + selector + "\\s*\\{([^}]*)\\}", "gi");
        var m;
        while ((m = rules.exec(html)) !== null) {
            var v = pick(new RegExp("(?:^|;)\\s*" + prop + "\\s*:\\s*([^;]+)", "i"), m[1]);
            if (v) out = v;
        }
        return out.trim();
    }
    function attrStyle(html, prop) {
        var tag = pick(/<body\b([^>]*)>/i, html);
        if (!tag) return "";
        var st = pick(/style\s*=\s*"([^"]*)"/i, tag) || pick(/style\s*=\s*'([^']*)'/i, tag);
        return st ? pick(new RegExp("(?:^|;)\\s*" + prop + "\\s*:\\s*([^;]+)", "i"), st).trim() : "";
    }

    // words that appear in a background shorthand and are not colours
    readonly property var notColours: ["none", "transparent", "inherit", "initial", "unset", "auto",
        "repeat", "repeat-x", "repeat-y", "no-repeat", "fixed", "scroll", "local", "cover", "contain",
        "center", "top", "bottom", "left", "right", "padding-box", "border-box", "content-box", "important"]
    function colorOf(v, fallback) {
        if (!v) return fallback;
        // background: #111 url(...) no-repeat — the colour is the part Qt knows
        var parts = v.replace(/url\([^)]*\)/gi, " ").replace(/!important/gi, " ")
                     .replace(/(rgba?|hsla?)\s*\(([^)]*)\)/gi, function(m) { return m.replace(/\s+/g, ""); })
                     .trim().split(/\s+/);
        for (var i = 0; i < parts.length; i++) {
            var s = parts[i].replace(/[,;]+$/, "");
            var named = /^[a-z]+$/i.test(s) && browser.notColours.indexOf(s.toLowerCase()) < 0;
            if (!/^#[0-9a-f]{3,8}$/i.test(s) && !/^(rgba?|hsla?)\(/i.test(s) && !named) continue;
            var c = Qt.color(s);
            // an unknown name comes back invalid, which QML hands over as
            // fully transparent black — not something anyone wrote on purpose
            if (c && !(c.r === 0 && c.g === 0 && c.b === 0 && c.a === 0)) return c;
        }
        return fallback;
    }
    function light(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.5; }

    // what this browser cannot do, counted rather than hidden
    readonly property var cannot: [
        { re: /<script\b/gi, name: "script" },
        { re: /<canvas\b/gi, name: "canvas" },
        { re: /<video\b/gi, name: "video" },
        { re: /<audio\b/gi, name: "audio" },
        { re: /<iframe\b/gi, name: "iframe" },
        { re: /<svg\b/gi, name: "svg" },
        { re: /<input\b|<button\b|<select\b|<textarea\b/gi, name: "form control" },
        { re: /display\s*:\s*flex/gi, name: "flexbox" },
        { re: /display\s*:\s*grid/gi, name: "grid" },
        { re: /@keyframes|animation\s*:|transition\s*:/gi, name: "animation" }
    ]
    function unsupported(html) {
        var bits = [];
        for (var i = 0; i < browser.cannot.length; i++) {
            var c = browser.cannot[i], n = (html.match(c.re) || []).length;
            if (n) bits.push(c.name + (n > 1 ? " ×" + n : ""));
        }
        return bits.join(" · ");
    }

    // Qt's importer draws what it knows and prints what it doesn't, so the
    // parts that would show up as stray text are taken out first.
    function prepare(html) {
        return html
            .replace(/<!--[\s\S]*?-->/g, "")
            .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, "")
            .replace(/<script\b[^>]*>[\s\S]*$/i, "")
            .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript\s*>/gi, "")
            .replace(/<(meta|link|base)\b[^>]*>/gi, "");
    }

    // A browser comes with its own style sheet before the page's: <pre> and
    // <code> are fixed-width. Qt's importer has no such defaults, so the page
    // is handed them first — first means the page's own rules still win.
    function defaults() {
        var mono = firstFamily(browser.families.monospace);
        if (!mono) return "";
        return "<style>pre, code, tt, kbd, samp { font-family: '" + mono + "'; }</style>";
    }
    function withDefaults(html) {
        var css = defaults();
        if (!css) return html;
        var m = /<head\b[^>]*>/i.exec(html) || /<html\b[^>]*>/i.exec(html);
        if (m) return html.slice(0, m.index + m[0].length) + css + html.slice(m.index + m[0].length);
        return css + html;
    }

    // everything the view needs to draw one page, worked out once
    function parse(raw, url) {
        var clean = prepare(raw);
        var bg = colorOf(attrStyle(clean, "background-color") || attrStyle(clean, "background")
                         || cssOf(clean, "body", "background-color") || cssOf(clean, "body", "background")
                         || pick(/<body[^>]*\bbgcolor\s*=\s*["']?([^"'\s>]+)/i, clean), Qt.color("#ffffff"));
        return {
            url: url,
            raw: raw,
            body: withDefaults(clean),
            title: pick(/<title[^>]*>([\s\S]*?)<\/title\s*>/i, clean).replace(/\s+/g, " ").trim()
                   || url.replace(/^.*\//, "") || "untitled",
            bg: bg,
            ink: colorOf(attrStyle(clean, "color") || cssOf(clean, "body", "color")
                         || pick(/<body[^>]*\btext\s*=\s*["']?([^"'\s>]+)/i, clean),
                         Qt.color(light(bg) ? "#101014" : "#e9e9ee")),
            family: familyOf(attrStyle(clean, "font-family") || cssOf(clean, "body", "font-family")),
            elements: (clean.match(/<[a-zA-Z][^>]*>/g) || []).length,
            missing: unsupported(raw)
        };
    }

    // ── the pages this machine has ──────────────────────────────────────────

    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function baseName(u) {
        var s = String(u).split("#")[0].split("?")[0];
        s = s.replace(/^.*\//, "");
        return s.toLowerCase();
    }
    // 50-hello-page.html is also just hello-page.html, the way anyone would
    // type it, and the .html may be left off entirely
    function keysOf(file) {
        var b = baseName(file), noNum = b.replace(/^\d+[-_]/, "");
        return [b, noNum, b.replace(/\.html?$/, ""), noNum.replace(/\.html?$/, "")];
    }
    function findPage(url) {
        var want = baseName(url);
        if (!want) return null;
        var bare = want.replace(/\.html?$/, "");
        for (var i = 0; i < browser.site.length; i++) {
            var k = keysOf(browser.site[i].file);
            if (k.indexOf(want) >= 0 || k.indexOf(bare) >= 0) return browser.site[i];
        }
        return null;
    }

    function rowsFor(group) {
        var rows = "";
        for (var i = 0; i < browser.site.length; i++) {
            var p = browser.site[i];
            if ((p.group || "yours") !== group) continue;
            rows += '<tr><td><a href="' + esc(p.file) + '">' + esc(p.title || p.file) + '</a></td>' +
                    '<td><font color="#8c8279">' + esc(p.about || "") + '</font></td></tr>';
        }
        return rows ? '<table cellpadding="6" cellspacing="0" width="100%">' + rows + '</table>' : "";
    }
    function startPage() {
        var mine = rowsFor("yours"), theirs = rowsFor("samples");
        var body = "";
        if (mine) body += '<h2>your pages</h2>' + mine;
        if (theirs) body += '<h3>samples</h3>' + theirs;
        if (!body) body = '<p><font color="#8c8279">nothing here yet</font></p>';
        return '<!doctype html><html><head><title>new tab</title>' +
               '<style>body { background-color: #f7f5f2; color: #2a2520; } h2, h3 { color: #7a4b52; }</style>' +
               '</head><body>' + body +
               '<p><font color="#8c8279" size="2">ctrl+t another tab &middot; ctrl+w close this one &middot; ' +
               'ctrl+tab switch &middot; alt+&larr; back &middot; esc back to your page</font></p>' +
               '</body></html>';
    }
    function errorPage(url, why, detail) {
        return '<!doctype html><html><head><title>' + esc(why) + '</title>' +
               '<style>body { background-color: #fbf7f2; color: #241f1c; } h1 { color: #b5838d; }</style>' +
               '</head><body><h1>' + esc(why) + '</h1>' +
               '<p><tt>' + esc(url) + '</tt></p><p>' + detail + '</p>' +
               '<p><a href="about:newtab">the start page</a></p></body></html>';
    }
    // what a url resolves to: a page here, or an error page written on the spot
    function fetch(url) {
        // the start page is also what "/" and index.html mean here
        if (/^about:(newtab|blank)$/i.test(url) || /^\/?(index\.html?)?$/i.test(url.trim()))
            return { url: "about:newtab", raw: startPage() };
        if (/^(https?|ftp|mailto|tel):/i.test(url))
            return { url: url, raw: errorPage(url, "you are offline",
                     "and always will be — this browser has no network at all. " +
                     "It only ever draws pages that are already on this machine.") };
        var p = findPage(url);
        if (p) return { url: browser.root + p.file, raw: p.raw };
        return { url: url, raw: errorPage(url, "no such page",
                 "there is no file by that name in <tt>snippets/</tt>, and nothing to go online for.") };
    }

    // ── tabs ────────────────────────────────────────────────────────────────

    function bump() { browser.tabs = browser.tabs.slice(); }
    function keep() {                                  // remember where we were
        if (!browser.tab) return;
        browser.tab.scrollY = view.contentY;
    }
    function newTab(raw, url) {
        var t = parse(raw, url);
        t.zoom = 1;
        t.scrollY = 0;
        t.hist = [{ url: t.url, raw: raw }];
        t.hpos = 0;
        return t;
    }
    function addTab(raw, url) {
        keep();
        var list = browser.tabs.slice();
        list.push(newTab(raw, url));
        browser.tabs = list;
        select(list.length - 1);
    }
    function select(i) {
        if (i < 0 || i >= browser.tabs.length || i === browser.current) return;
        keep();
        browser.current = i;
        browser.hovered = "";
        view.contentY = browser.tab.scrollY || 0;
        sweep.restart();
    }
    function closeTab(i) {
        if (i < 0 || i >= browser.tabs.length) return;
        if (browser.tabs.length === 1) { browser.closeAll(); return; }
        keep();
        var list = browser.tabs.slice();
        list.splice(i, 1);
        var c = browser.current > i ? browser.current - 1 : Math.min(browser.current, list.length - 1);
        browser.current = -1;                          // so select() really re-reads
        browser.tabs = list;
        browser.current = c;
        view.contentY = browser.tab.scrollY || 0;
        browser.hovered = "";
    }
    function cycle(d) {
        if (browser.tabs.length < 2) return;
        select((browser.current + d + browser.tabs.length) % browser.tabs.length);
    }

    // ── going somewhere ─────────────────────────────────────────────────────

    function show(t, got) {
        var fresh = parse(got.raw, got.url);
        fresh.zoom = t.zoom;
        fresh.scrollY = 0;
        fresh.hist = t.hist;
        fresh.hpos = t.hpos;
        browser.tabs[browser.current] = fresh;
        bump();
        view.contentY = 0;
        browser.hovered = "";
        sweep.restart();
    }
    function go(url) {
        var t = browser.tab;
        if (!t) return;
        var got = fetch(url);
        t.hist = t.hist.slice(0, t.hpos + 1);
        t.hist.push({ url: got.url, raw: got.raw });
        t.hpos = t.hist.length - 1;
        show(t, got);
    }
    // Going back, forward or reloading asks the site for the page again
    // rather than showing the copy it kept, so a file you changed in the
    // editor is the file you see here — that is the whole point of having
    // both open at once.
    function again(entry) {
        var got = fetch(entry.url);
        return got.raw ? got : entry;
    }
    function step(d) {
        var t = browser.tab;
        if (!t) return;
        var n = t.hpos + d;
        if (n < 0 || n >= t.hist.length) return;
        t.hpos = n;
        show(t, again(t.hist[n]));
    }
    readonly property bool canBack: browser.tab ? browser.tab.hpos > 0 : false
    readonly property bool canForward: browser.tab ? browser.tab.hpos < browser.tab.hist.length - 1 : false

    function clicked(link) {
        if (/^#/.test(link)) {
            flash("the whole page is already here — anchors have nowhere to jump to");
            return;
        }
        go(link);
    }
    function reload() {
        var t = browser.tab;
        if (t) show(t, again(t.hist[t.hpos]));
    }

    // ── the way in and out ──────────────────────────────────────────────────

    // Called with whatever is on the page in CODE: a new tab every time, so
    // the version before this one is still open next door. Esc only hides the
    // browser — the tabs are still there when you run the next one, the way
    // they would be if you had put the window away. Running the same text
    // twice doesn't stack: it goes back to the tab that already has it.
    readonly property int maxTabs: 12
    function open(raw, file) {
        var mine = browser.root + (file || browser.ownFile);
        var found = -1;
        for (var i = 0; i < browser.tabs.length; i++)
            if (browser.tabs[i].url === mine && browser.tabs[i].raw === raw) found = i;
        if (found >= 0 && found !== browser.current) select(found);
        else if (found >= 0) { view.contentY = 0; sweep.restart(); }
        else {
            addTab(raw, mine);
            if (browser.tabs.length > browser.maxTabs) {
                var list = browser.tabs.slice(browser.tabs.length - browser.maxTabs);
                browser.current -= browser.tabs.length - browser.maxTabs;
                browser.tabs = list;
            }
        }
        clearLater.stop();
        browser.running = true;
        browser.forceActiveFocus();
        return true;
    }
    function openStart() { addTab(startPage(), "about:newtab"); }
    // Esc puts the browser away; closing the last tab really closes it
    function stop() {
        if (!browser.running) return;
        browser.running = false;
        browser.stopped();
    }
    function closeAll() {
        stop();
        clearLater.restart();          // after the fade, so nothing blanks first
    }
    Timer {
        id: clearLater
        interval: 320
        onTriggered: {
            if (browser.running) return;
            browser.tabs = [];
            browser.current = -1;
        }
    }

    onActiveFocusChanged: if (!activeFocus && running) refocus.restart()
    Timer {
        id: refocus
        interval: 0
        onTriggered: {
            // only if nothing of its own took it (a text box inside it) and the
            // window itself still has the keyboard
            if (browser.running && !browser.activeFocus && Window.window && Window.window.active
                    && !(Window.activeFocusItem && browser.isAncestorOf(Window.activeFocusItem)))
                browser.forceActiveFocus();
        }
    }
    function isAncestorOf(item) {
        for (var p = item; p; p = p.parent) if (p === browser) return true;
        return false;
    }

    NumberAnimation {
        id: sweep
        target: browser; property: "loaded"
        from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic
    }

    function flash(msg) {
        nowhereText.text = msg;
        nowhere.restart();
    }

    // ── chrome ──────────────────────────────────────────────────────────────

    Rectangle { anchors.fill: parent; color: "#1b1b1f" }

    // Everything under the browser is still there — the page, the file list,
    // the mode tabs — and a click on a blank bit of chrome used to fall
    // through to them, hand the keyboard to the hidden editor, and leave the
    // browser on screen deaf to Esc. It catches every press, wheel and hover
    // itself now, and takes the keyboard back on any click.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: browser.forceActiveFocus()
        onWheel: function(ev) { ev.accepted = true; }
    }

    Rectangle {
        id: chrome
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 84
        color: "#2a2a30"

        // the tab strip: as many pages as you have open, sharing the width
        Item {
            id: strip
            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 14
                      top: parent.top; topMargin: 8 }
            height: 30

            readonly property int count: browser.tabs.length
            readonly property real slot: Math.max(74, Math.min(220, (strip.width - 26) / Math.max(1, strip.count)))

            Row {
                spacing: 4
                Repeater {
                    model: browser.tabs
                    delegate: Rectangle {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool active: index === browser.current
                        width: strip.slot
                        height: 30
                        radius: 8
                        color: active ? "#3a3a42" : (tabHover.hovered ? "#33333b" : "#2f2f36")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: tabHover }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(m) {
                                if (m.button === Qt.MiddleButton) browser.closeTab(tabItem.index);
                                else browser.select(tabItem.index);
                            }
                        }
                        Rectangle {
                            id: favicon
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 4
                            color: tabItem.active ? (w ? w.cAccent : "#b5838d") : "#5a5a66"
                            Text {
                                anchors.centerIn: parent
                                text: (tabItem.modelData.title || "?").charAt(0).toUpperCase()
                                font.family: w ? w.fontFamily : ""
                                font.pixelSize: 10
                                font.bold: true
                                color: "#1b1b1f"
                            }
                        }
                        Text {
                            anchors { left: favicon.right; leftMargin: 8
                                      right: parent.right; rightMargin: tabItem.width > 130 ? 22 : 6
                                      verticalCenter: parent.verticalCenter }
                            textFormat: Text.PlainText
                            text: tabItem.active && browser.loaded < 1 ? "loading…" : tabItem.modelData.title
                            elide: Text.ElideRight
                            font.family: w ? w.fontFamily : ""
                            font.pixelSize: 12
                            color: tabItem.active ? "#e6e6ea" : "#a6a6b0"
                        }
                        Text {
                            visible: tabItem.width > 130
                            anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                            text: "✕"
                            font.family: w ? w.fontFamily : ""
                            font.pixelSize: 11
                            color: closeHover.hovered ? "#ffffff" : "#8a8a95"
                            HoverHandler { id: closeHover }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: browser.closeTab(tabItem.index)
                            }
                        }
                    }
                }
            }
            Text {
                x: Math.min(strip.width - 16, strip.count * (strip.slot + 4) + 6)
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 16
                color: plusHover.hovered ? "#ffffff" : "#8a8a95"
                HoverHandler { id: plusHover }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -7
                    cursorShape: Qt.PointingHandCursor
                    onClicked: browser.openStart()
                }
            }
        }

        // back and forward are lit only when this tab has somewhere to go
        Row {
            id: navBtns
            x: 12; y: 48
            spacing: 14
            Text {
                text: "‹"
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 16
                color: browser.canBack ? (backHover.hovered ? "#ffffff" : "#c8c8d0") : "#55555f"
                HoverHandler { id: backHover; enabled: browser.canBack }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    enabled: browser.canBack
                    cursorShape: Qt.PointingHandCursor
                    onClicked: browser.step(-1)
                }
            }
            Text {
                text: "›"
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 16
                color: browser.canForward ? (fwdHover.hovered ? "#ffffff" : "#c8c8d0") : "#55555f"
                HoverHandler { id: fwdHover; enabled: browser.canForward }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    enabled: browser.canForward
                    cursorShape: Qt.PointingHandCursor
                    onClicked: browser.step(1)
                }
            }
            Text {
                text: "↻"
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 16
                color: reloadHover.hovered ? "#ffffff" : "#c8c8d0"
                HoverHandler { id: reloadHover }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: browser.reload()
                }
            }
        }

        Rectangle {
            id: bar
            anchors { left: navBtns.right; leftMargin: 14; right: parent.right; rightMargin: 14
                      verticalCenter: navBtns.verticalCenter }
            height: 26
            radius: 13
            color: "#1f1f25"
            clip: true

            // the load sweep, the one thing in this chrome that is telling
            // the truth about work being done
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * browser.loaded
                color: Qt.alpha(w ? w.cAccent : "#b5838d", 0.22)
                opacity: browser.loaded < 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
            Text {
                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                textFormat: Text.PlainText
                text: "⌂  " + (browser.tab ? browser.tab.url : "")
                      + (browser.tab && browser.tab.zoom !== 1 ? "      " + Math.round(browser.tab.zoom * 100) + "%" : "")
                elide: Text.ElideMiddle
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 12
                color: "#9a9aa4"
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: "#121215"
        }
    }

    // ── the page ────────────────────────────────────────────────────────────

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: chrome.bottom; bottom: status.top }
        color: browser.tab ? browser.tab.bg : "#ffffff"
        clip: true

        Flickable {
            id: view
            anchors.fill: parent
            contentWidth: width
            contentHeight: doc.implicitHeight + 64
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3500
            opacity: browser.loaded
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Text {
                id: doc
                x: 32; y: 32
                width: Math.max(120, view.width - 64)
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                text: browser.tab ? browser.tab.body : ""
                font.family: (browser.tab && browser.tab.family) || browser.pageFont
                font.pixelSize: Math.round(16 * (browser.tab ? browser.tab.zoom : 1))
                color: browser.tab ? browser.tab.ink : "#101014"
                linkColor: browser.tab && !light(browser.tab.bg) ? "#8fb2ff" : "#1a3ecc"
                onLinkHovered: function(link) { browser.hovered = link; }
                onLinkActivated: function(link) { browser.clicked(link); }
            }
        }

        // a word about what just didn't happen
        Rectangle {
            id: nowhereBox
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
            width: nowhereText.implicitWidth + 28
            height: 30
            radius: 15
            color: "#1b1b1f"
            opacity: 0
            Text {
                id: nowhereText
                anchors.centerIn: parent
                text: ""
                font.family: w ? w.fontFamily : ""
                font.pixelSize: 12
                color: "#e6e6ea"
            }
            SequentialAnimation {
                id: nowhere
                NumberAnimation { target: nowhereBox; property: "opacity"; to: 0.95; duration: 120 }
                PauseAnimation { duration: 1600 }
                NumberAnimation { target: nowhereBox; property: "opacity"; to: 0; duration: 260 }
            }
        }

        // a scrollbar, drawn rather than imported
        Rectangle {
            readonly property bool pale: browser.tab ? light(browser.tab.bg) : true
            anchors { right: parent.right; rightMargin: 3 }
            width: 5
            radius: 2.5
            visible: view.contentHeight > view.height + 1
            color: pale ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(1, 1, 1, 0.3)
            height: Math.max(30, view.height * view.height / Math.max(1, view.contentHeight))
            y: (view.height - height) * (view.contentHeight > view.height
                 ? Math.max(0, Math.min(1, view.contentY / (view.contentHeight - view.height))) : 0)
        }
    }

    // ── status line — the console this browser has instead of devtools ──────

    Rectangle {
        id: status
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 26
        color: "#2a2a30"
        Text {
            anchors { left: parent.left; leftMargin: 14; right: keysHint.left; rightMargin: 12
                      verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: browser.hovered ? "→ " + browser.hovered
                : browser.loaded < 1 ? "loading…"
                : !browser.tab ? ""
                : browser.tab.elements + (browser.tab.elements === 1 ? " element" : " elements") + " drawn"
                  + (browser.tabs.length > 1 ? "   ·   " + browser.tabs.length + " pages open" : "")
                  + (browser.tab.missing ? "   ·   not drawn: " + browser.tab.missing : "")
            font.family: w ? w.fontFamily : ""
            font.pixelSize: 11
            color: browser.tab && browser.tab.missing && !browser.hovered ? "#d8a05e" : "#9a9aa4"
        }
        Text {
            id: keysHint
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: "ctrl+t tab   ·   ctrl+w close   ·   ctrl+tab switch   ·   esc back"
            font.family: w ? w.fontFamily : ""
            font.pixelSize: 11
            color: "#6d6d78"
        }
    }

    Keys.onPressed: function(e) {
        e.accepted = true;
        var ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        var alt = (e.modifiers & Qt.AltModifier) !== 0;
        var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
        if (e.key === Qt.Key_Escape) { browser.stop(); return; }
        if (ctrl && e.key === Qt.Key_T) { browser.openStart(); return; }
        if (ctrl && e.key === Qt.Key_W) { browser.closeTab(browser.current); return; }
        if (ctrl && e.key === Qt.Key_R) { browser.reload(); return; }
        if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
            browser.cycle(shift || e.key === Qt.Key_Backtab ? -1 : 1);
            return;
        }
        if ((alt && e.key === Qt.Key_Left) || e.key === Qt.Key_Back || e.key === Qt.Key_Backspace) {
            browser.step(-1); return;
        }
        if (alt && e.key === Qt.Key_Right) { browser.step(1); return; }
        if ((ctrl || alt) && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
            browser.select(Math.min(browser.tabs.length, e.key - Qt.Key_0) - 1);
            return;
        }
        if (ctrl && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) zoomBy(0.1);
        else if (ctrl && e.key === Qt.Key_Minus) zoomBy(-0.1);
        else if (ctrl && e.key === Qt.Key_0) zoomBy(0);
        else if (e.key === Qt.Key_Home) view.contentY = 0;
        else if (e.key === Qt.Key_End) view.contentY = Math.max(0, view.contentHeight - view.height);
        else if (e.key === Qt.Key_PageDown) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height),
                                                                    view.contentY + view.height * 0.9);
        else if (e.key === Qt.Key_PageUp) view.contentY = Math.max(0, view.contentY - view.height * 0.9);
        else if (e.key === Qt.Key_Down) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height),
                                                                 view.contentY + 60);
        else if (e.key === Qt.Key_Up) view.contentY = Math.max(0, view.contentY - 60);
    }

    function zoomBy(d) {
        if (!browser.tab) return;
        browser.tab.zoom = d === 0 ? 1 : Math.max(0.5, Math.min(3, browser.tab.zoom + d));
        bump();
    }
}
