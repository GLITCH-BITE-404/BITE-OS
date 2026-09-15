// What you typed, held up against the ghost — line by line and word by word.
//
// Comparing character by character from the top means one extra space shifts
// everything after it one place, and the whole rest of the page goes red for a
// single slip. Comparing each line to its own ghost line, word for word, means a
// mistake costs the word it is in and nothing else, double spaces don't count,
// and indentation never counts at all (that's what code has, and it isn't what
// anyone is trying to get right).

.pragma library

function tokens(line) {
    var out = [], re = /\S+/g, m;
    while ((m = re.exec(line)) !== null) out.push({ s: m.index, e: m.index + m[0].length, w: m[0] });
    return out;
}

// -> { bad: [per character], view: [{col, text} per row — the part of the
//      ghost still to type, starting where that row's typing ends],
//      wrong: words, correct: characters, complete, widest }
function align(text, ghost) {
    var lines = text.split("\n");
    var bad = new Array(text.length);
    for (var i = 0; i < bad.length; i++) bad[i] = false;
    var view = [], wrong = 0, correct = 0, complete = true, off = 0, widest = 0;
    var rows = Math.max(lines.length, ghost.length);

    for (var r = 0; r < rows; r++) {
        var g = r < ghost.length ? ghost[r] : "";
        var gt = tokens(g);
        if (r >= lines.length) {
            view.push({ col: 0, text: g });
            if (gt.length) complete = false;
            continue;
        }
        var t = lines[r], tt = tokens(t), current = r === lines.length - 1;
        widest = Math.max(widest, t.length);

        for (var j = 0; j < tt.length; j++) {
            var a = tt[j], b = j < gt.length ? gt[j] : null;
            var done = a.e < t.length || !current;        // something came after it
            if (b && a.w === b.w) { correct += a.w.length + (done ? 1 : 0); continue; }
            if (b && !done && b.w.indexOf(a.w) === 0) { correct += a.w.length; continue; }
            wrong++;
            // a finished word that's wrong is wrong all over; the one still
            // being typed only goes red from the first slip onward
            var from = 0;
            if (b && !done) {
                while (from < a.w.length && a.w[from] === b.w[from]) from++;
                correct += from;
            }
            for (var k = from; k < a.w.length; k++) bad[off + a.s + k] = true;
        }
        if (!current && tt.length < gt.length) wrong += gt.length - tt.length;

        if (tt.length !== gt.length) complete = false;
        else for (j = 0; j < tt.length; j++) if (tt[j].w !== gt[j].w) { complete = false; break; }

        var rest = "";
        if (!tt.length) {
            var lead = g.length - g.replace(/^\s+/, "").length;
            rest = t.length <= lead ? g.substr(t.length) : g.substr(lead);
        } else if (/\s$/.test(t)) {
            rest = tt.length < gt.length ? g.substr(gt[tt.length].s) : "";
        } else {
            var last = tt[tt.length - 1], gb = tt.length - 1 < gt.length ? gt[tt.length - 1] : null;
            if (gb) rest = (last.w.length < gb.w.length && gb.w.indexOf(last.w) === 0)
                           ? g.substr(gb.s + last.w.length) : g.substr(gb.e);
        }
        view.push({ col: t.length, text: rest });
        off += t.length + 1;
    }
    return { bad: bad, view: view, wrong: wrong, correct: correct,
             complete: complete && text.length > 0, widest: widest };
}

// Where the typing is (the end of the text), against its ghost line.
function state(text, ghost) {
    var lines = text.split("\n"), r = lines.length - 1, t = lines[r];
    var g = r < ghost.length ? ghost[r] : "", tt = tokens(t), gt = tokens(g);
    var between = !tt.length || /\s$/.test(t);
    var j = between ? tt.length : tt.length - 1;
    return { row: r, typed: tt.length, words: gt.length, between: between,
             word: j < gt.length ? gt[j].w : null, partial: between ? "" : tt[tt.length - 1].w };
}

// What a key should really insert when a line is finished and you keep going:
// a space at the end of the last word, or a letter after it, drops you onto
// the next line instead of piling onto this one. null = type it as it is.
function autoline(s, key) {
    if (!s.words) return null;
    if (key === " ") {
        if (!s.between && s.typed === s.words && s.word !== null && s.partial.length >= s.word.length) return "\n";
        if (s.between && s.typed >= s.words) return "\n";
        return null;
    }
    if (s.between && s.typed >= s.words) return "\n" + key;
    return null;
}

// The character the ghost wants next, for strict mode. "" = anything goes.
function expected(s) {
    if (s.between) return s.word === null ? "\n" : s.word[0];
    if (s.word === null) return "\n";
    return s.partial.length < s.word.length ? s.word[s.partial.length] : (s.typed >= s.words ? "\n" : " ");
}
