// What you typed, held up against the ghost.
//
// Two ways, because two kinds of typing want different things:
//
//  slots() — LYRICS and SPEED. Every key fills the next letter's slot and the
//            line never moves: a wrong letter stays red where it stands and
//            the next letter is judged against its own slot, so you just carry
//            on. Nothing you type can push the ghost along or off the screen.
//            A space mid-word skips to the next word (the skipped letters are
//            filled with FILL and shown in red); extra letters are refused by
//            the page before they get here.
//
//  align() — CODE, where you're free to write what you like. Each line is held
//            against its own ghost line word by word, so a change costs the
//            word it's in and nothing after it, and indentation never counts.
//            The ghost stays where it is either way.

.pragma library

var FILL = "\ue000";     // a skipped letter's slot — blank on the page. Private-use,
                          // not U+00A0: TextEdit hands every non-breaking space back as a plain one

function tokens(line) {
    var out = [], re = /[^\s\ue000]+/g, m;
    while ((m = re.exec(line)) !== null) out.push({ s: m.index, e: m.index + m[0].length, w: m[0] });
    return out;
}

function blankBad(n) {
    var bad = new Array(n);
    for (var i = 0; i < n; i++) bad[i] = false;
    return bad;
}

// -> { bad: [per character], view: [{col, text, missed} per row], wrong,
//      correct: characters, complete, widest }
function slots(text, ghost) {
    var lines = text.split("\n"), bad = blankBad(text.length), view = [];
    var wrong = 0, correct = 0, off = 0, widest = 0;
    var complete = text.length > 0 && lines.length >= ghost.length;

    for (var r = 0; r < Math.max(lines.length, ghost.length); r++) {
        var g = r < ghost.length ? ghost[r] : "";
        var t = r < lines.length ? lines[r] : "";
        if (r < ghost.length ? t !== g : t.length > 0) complete = false;
        widest = Math.max(widest, t.length);

        // the ghost shows wherever nothing real was typed; skipped letters
        // get their own layer so they can be red
        var mask = "", miss = "";
        for (var k = 0; k < Math.max(t.length, g.length); k++) {
            var tc = k < t.length ? t[k] : null, gc = k < g.length ? g[k] : " ";
            mask += tc === null ? gc : " ";
            miss += tc === FILL && gc !== " " ? gc : " ";
            if (tc === null) continue;
            if (tc === FILL) { if (gc !== " ") wrong++; continue; }
            if (tc === gc) correct++;
            else { bad[off + k] = true; wrong++; }
        }
        view.push({ col: 0, text: mask.replace(/\s+$/, ""), missed: miss.replace(/\s+$/, "") });
        if (r < lines.length) off += t.length + 1;
    }
    return { bad: bad, view: view, wrong: wrong, correct: correct, complete: complete, widest: widest };
}

function align(text, ghost) {
    var lines = text.split("\n"), bad = blankBad(text.length), view = [];
    var wrong = 0, correct = 0, complete = true, off = 0, widest = 0;
    var rows = Math.max(lines.length, ghost.length);

    for (var r = 0; r < rows; r++) {
        var g = r < ghost.length ? ghost[r] : "";
        var gt = tokens(g);
        if (r >= lines.length) {
            view.push({ col: 0, text: g, missed: "" });
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

        // the ghost keeps its own place: whatever of it lies past the end of
        // what you've typed, where it always was
        view.push({ col: t.length, text: g.substr(t.length), missed: "" });
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

// The character the ghost wants next, for CODE's strict mode. "" = anything.
function expected(s) {
    if (s.between) return s.word === null ? "\n" : s.word[0];
    if (s.word === null) return "\n";
    return s.partial.length < s.word.length ? s.word[s.partial.length] : (s.typed >= s.words ? "\n" : " ");
}
