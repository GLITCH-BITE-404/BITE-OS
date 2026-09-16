// Just enough of the Unicode bidi algorithm for a monospace grid of letters.
//
// Every letter on the page is its own item on a grid, so nothing reorders
// text for us the way a normal text box would — without this, Hebrew and
// Arabic come out back to front. This handles what people actually type:
// Hebrew or Arabic lines with English words and numbers in them, English
// with a Hebrew word in it, and a Hebrew comment in a line of code. Levels
// 0–2, no explicit embedding controls.
//
// Also here: how many cells a character takes. Wide characters (Chinese,
// Japanese, Korean, emoji) take two; accents, Hebrew vowel points and the
// second half of an emoji take none and ride on the character before them.

.pragma library

function isMark(c) {
    return (c >= 0x0300 && c <= 0x036F) || (c >= 0x0483 && c <= 0x0489) ||
           (c >= 0x0591 && c <= 0x05BD) || c === 0x05BF || c === 0x05C1 || c === 0x05C2 ||
           c === 0x05C4 || c === 0x05C5 || c === 0x05C7 ||
           (c >= 0x0610 && c <= 0x061A) || (c >= 0x064B && c <= 0x065F) || c === 0x0670 ||
           (c >= 0x06D6 && c <= 0x06DC) || (c >= 0x06DF && c <= 0x06E4) || c === 0x06E7 || c === 0x06E8 ||
           (c >= 0x06EA && c <= 0x06ED) || (c >= 0x0E31 && c <= 0x0E3A && c !== 0x0E32 && c !== 0x0E33) ||
           c === 0x200D || (c >= 0x20D0 && c <= 0x20FF) || (c >= 0xFE00 && c <= 0xFE0F);
}

function isWide(c) {
    return (c >= 0x1100 && c <= 0x115F) || (c >= 0x2E80 && c <= 0x303E) || (c >= 0x3041 && c <= 0x33FF) ||
           (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xA000 && c <= 0xA4CF) ||
           (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE4F) ||
           (c >= 0xFF00 && c <= 0xFF60) || (c >= 0xFFE0 && c <= 0xFFE6);
}

// cells taken by the UTF-16 unit at i: 0, 1 or 2
function width(s, i) {
    var c = s.charCodeAt(i);
    if (c >= 0xDC00 && c <= 0xDFFF && i > 0) {
        var p = s.charCodeAt(i - 1);
        if (p >= 0xD800 && p <= 0xDBFF) return 0;
    }
    if (c >= 0xD800 && c <= 0xDBFF) {
        var cp = s.codePointAt(i);
        // skin tones and tag characters modify the emoji before them, and
        // anything after a zero-width joiner is part of the same picture
        if ((cp >= 0x1F3FB && cp <= 0x1F3FF) || (cp >= 0xE0020 && cp <= 0xE007F)) return 0;
        if (i > 0 && s.charCodeAt(i - 1) === 0x200D) return 0;
        return 2;
    }
    if (i > 0 && s.charCodeAt(i - 1) === 0x200D && c !== 10) return 0;
    if (isMark(c)) return 0;
    if (isWide(c)) return 2;
    return 1;
}

// "R" right-to-left letter, "L" left-to-right letter, "D" digit, "N" neutral
function kind(ch) {
    if (!ch || !ch.length) return "N";
    var c = ch.codePointAt(0);
    if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFC)) return "R";
    if (c >= 0x30 && c <= 0x39) return "D";
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) ||
        (c >= 0xC0 && c <= 0x2AF && c !== 0xD7 && c !== 0xF7) ||
        (c >= 0x370 && c <= 0x58F) || (c >= 0x900 && c <= 0x1FFF) || (c >= 0x2C00 && c <= 0x2DFF) ||
        (c >= 0x3040 && c <= 0xD7FF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF21 && c <= 0xFF5A)) return "L";
    return "N";
}

// the first strong letter decides a paragraph: 1 right-to-left, 0 left-to-right,
// -1 when there isn't one yet
function strong(text) {
    for (var i = 0; i < text.length; i++) {
        var k = kind(text[i]);
        if (k === "R") return 1;
        if (k === "L") return 0;
    }
    return -1;
}

var MIRROR = { "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{",
               "<": ">", ">": "<", "«": "»", "»": "«" };

// a bracket in a right-to-left run faces the other way
function mirror(ch, odd) {
    return odd && MIRROR[ch] !== undefined ? MIRROR[ch] : ch;
}

// cells: one string per cell, in the order they were typed
// -> { order: cell indices left to right on screen, level: per cell }
function layout(cells, base) {
    var n = cells.length, level = new Array(n), dirs = new Array(n), i, j, t;
    var baseDir = base ? "R" : "L";

    // strong letters are what they are; a number takes the direction of the
    // last strong letter before it (so "שלום 123" keeps its number in the
    // Hebrew run, and "abc 123" in the English one)
    var last = baseDir;
    for (i = 0; i < n; i++) {
        var k = kind(cells[i]);
        if (k === "R" || k === "L") { last = k; dirs[i] = k; level[i] = k === "R" ? 1 : (base ? 2 : 0); }
        else if (k === "D") { dirs[i] = last; level[i] = (base || last === "R") ? 2 : 0; }
        else dirs[i] = null;
    }

    // spaces and punctuation between two things going the same way go that
    // way too; otherwise they follow the paragraph (which also puts trailing
    // spaces where they belong)
    for (i = 0; i < n;) {
        if (dirs[i] !== null) { i++; continue; }
        j = i;
        while (j < n && dirs[j] === null) j++;
        var before = i > 0 ? dirs[i - 1] : baseDir;
        var after = j < n ? dirs[j] : baseDir;
        var d = before === after ? before : baseDir;
        var lv = d === "R" ? 1 : (base ? 2 : 0);
        for (t = i; t < j; t++) level[t] = lv;
        i = j;
    }

    // reverse every run at each level, highest first
    var order = [], maxL = 0;
    for (i = 0; i < n; i++) { order.push(i); maxL = Math.max(maxL, level[i]); }
    for (var L = maxL; L >= 1; L--) {
        i = 0;
        while (i < n) {
            if (level[order[i]] < L) { i++; continue; }
            j = i;
            while (j < n && level[order[j]] >= L) j++;
            for (var a = i, b = j - 1; a < b; a++, b--) { t = order[a]; order[a] = order[b]; order[b] = t; }
            i = j;
        }
    }
    return { order: order, level: level };
}
