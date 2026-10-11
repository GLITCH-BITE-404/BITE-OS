// CODE: what changed — the same view every other editor shows you, one column
// deep, the way git writes it.
//
// Two texts go in and a list of rows comes out: lines both sides share, lines
// only the old one has (−), lines only the new one has (+). The rows come from
// a longest-common-subsequence walk over the lines, so a line inserted in the
// middle moves everything below it down on one side only, instead of turning
// the rest of the file into a change.
//
// It compares this file with another one of yours, or with the last version of
// it you actually ran — which is the one you usually mean by "what did I just
// change?".

import QtQuick

Item {
    id: dv
    property var w
    property bool shown: false
    property string oldName: ""
    property string newName: ""
    property var rows: []
    property int added: 0
    property int removed: 0
    signal closed()

    readonly property color cAdd: (w && w.pal && w.pal.green) || "#a3b18a"
    readonly property color cDel: w ? w.cBad : "#e76f51"
    readonly property real lineH: 22
    readonly property int maxLines: 4000

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ── the diff itself ─────────────────────────────────────────────────────

    // Lines that both sides share, in order. The table is built over the two
    // line arrays; everything outside the common head and tail is what gets
    // walked, which keeps the usual case (a few edits in a long file) small.
    function build(a, b) {
        var out = [], i = 0, j = 0;
        var head = 0, tailA = a.length, tailB = b.length;
        while (head < a.length && head < b.length && a[head] === b[head]) head++;
        while (tailA > head && tailB > head && a[tailA - 1] === b[tailB - 1]) { tailA--; tailB--; }
        for (i = 0; i < head; i++) out.push({ kind: "same", o: i + 1, n: i + 1, text: a[i] });

        var mid = middle(a.slice(head, tailA), b.slice(head, tailB));
        for (i = 0; i < mid.length; i++) {
            var r = mid[i];
            out.push({ kind: r.kind,
                       o: r.o > 0 ? r.o + head : 0,
                       n: r.n > 0 ? r.n + head : 0,
                       text: r.text });
        }
        for (i = 0; i < a.length - tailA; i++)
            out.push({ kind: "same", o: tailA + i + 1, n: tailB + i + 1, text: a[tailA + i] });
        return out;
    }

    function middle(a, b) {
        var n = a.length, m = b.length, i, j;
        if (!n && !m) return [];
        if (!n || !m || n * m > 4000000) {
            var flat = [];
            for (i = 0; i < n; i++) flat.push({ kind: "del", o: i + 1, n: 0, text: a[i] });
            for (j = 0; j < m; j++) flat.push({ kind: "add", o: 0, n: j + 1, text: b[j] });
            return flat;
        }
        // lengths of the longest common subsequence, from the end backwards
        var L = new Array((n + 1) * (m + 1));
        for (i = n; i >= 0; i--) {
            for (j = m; j >= 0; j--) {
                L[i * (m + 1) + j] = (i === n || j === m) ? 0
                    : a[i] === b[j] ? L[(i + 1) * (m + 1) + j + 1] + 1
                    : Math.max(L[(i + 1) * (m + 1) + j], L[i * (m + 1) + j + 1]);
            }
        }
        var out = [];
        i = 0; j = 0;
        while (i < n && j < m) {
            if (a[i] === b[j]) { out.push({ kind: "same", o: i + 1, n: j + 1, text: a[i] }); i++; j++; }
            else if (L[(i + 1) * (m + 1) + j] >= L[i * (m + 1) + j + 1]) { out.push({ kind: "del", o: i + 1, n: 0, text: a[i] }); i++; }
            else { out.push({ kind: "add", o: 0, n: j + 1, text: b[j] }); j++; }
        }
        while (i < n) { out.push({ kind: "del", o: i + 1, n: 0, text: a[i] }); i++; }
        while (j < m) { out.push({ kind: "add", o: 0, n: j + 1, text: b[j] }); j++; }
        return out;
    }

    function open(oldText, oldTitle, newText, newTitle) {
        // an empty file has no lines at all, not one empty one
        var a = String(oldText).length ? String(oldText).split("\n") : [];
        var b = String(newText).length ? String(newText).split("\n") : [];
        if (a.length > dv.maxLines || b.length > dv.maxLines) {
            dv.rows = [{ kind: "same", o: 0, n: 0, text: "these are too long to compare line by line" }];
            dv.added = 0; dv.removed = 0;
        } else {
            var rows = build(a, b), add = 0, del = 0;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].kind === "add") add++;
                else if (rows[i].kind === "del") del++;
            }
            dv.rows = rows;
            dv.added = add;
            dv.removed = del;
        }
        dv.oldName = oldTitle;
        dv.newName = newTitle;
        view.contentY = 0;
        view.contentX = 0;
        dv.shown = true;
        dv.forceActiveFocus();
        // the first change is what you came to look at
        Qt.callLater(dv.toFirstChange);
    }
    function close() {
        if (!dv.shown) return;
        dv.shown = false;
        dv.closed();
    }

    function changeAt(from, d) {
        for (var i = from; i >= 0 && i < dv.rows.length; i += d)
            if (dv.rows[i].kind !== "same" && (i === 0 || dv.rows[i - 1].kind === "same")) return i;
        return -1;
    }
    function toFirstChange() {
        var i = changeAt(0, 1);
        if (i > 2) view.contentY = Math.min((i - 2) * dv.lineH, Math.max(0, view.contentHeight - view.height));
    }
    function jump(d) {
        var row = Math.round(view.contentY / dv.lineH) + (d > 0 ? 3 : -1);
        var i = changeAt(Math.max(0, Math.min(dv.rows.length - 1, row)), d);
        if (i >= 0) view.contentY = Math.max(0, Math.min((i - 2) * dv.lineH,
                                   Math.max(0, view.contentHeight - view.height)));
    }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.55 }
    MouseArea { anchors.fill: parent; onClicked: dv.close() }

    Rectangle {
        id: box
        width: Math.min(parent.width - 48, 1100)
        height: Math.min(parent.height - 56, 760)
        anchors.centerIn: parent
        radius: w.radius * 1.6
        color: w.cPage
        border.width: 1
        border.color: Qt.alpha(w.cAccent, 0.35)
        clip: true
        MouseArea { anchors.fill: parent }

        Text {
            id: head
            x: 22; y: 16
            width: parent.width - 44
            elide: Text.ElideMiddle
            text: "WHAT CHANGED"
            font.family: w.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 3
            color: w.cSub
        }
        Text {
            id: names
            x: 22; y: head.y + head.height + 8
            width: parent.width - 44
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: dv.oldName + "   →   " + dv.newName
            font.family: w.fontFamily
            font.pixelSize: 14
            color: w.cText
        }
        Row {
            id: tally
            anchors.right: parent.right
            anchors.rightMargin: 22
            y: head.y
            spacing: 12
            Text {
                visible: !dv.added && !dv.removed
                text: "no difference"
                font.family: w.fontFamily
                font.pixelSize: 13
                color: w.cSub
            }
            Text {
                visible: dv.added > 0
                text: "+" + dv.added
                font.family: w.fontFamily
                font.pixelSize: 13
                color: dv.cAdd
            }
            Text {
                visible: dv.removed > 0
                text: "−" + dv.removed
                font.family: w.fontFamily
                font.pixelSize: 13
                color: dv.cDel
            }
        }

        Rectangle {
            id: sheet
            x: 14
            y: names.y + names.height + 12
            width: parent.width - 28
            height: parent.height - y - 46
            radius: w.radius
            color: Qt.alpha(w.cBase, 0.6)
            clip: true

            readonly property real numW: Math.round(dv.lineH * 1.6)
            readonly property real signX: sheet.numW * 2 + 18
            readonly property real textX: sheet.signX + 16

            Flickable {
                id: view
                anchors.fill: parent
                anchors.margins: 6
                contentWidth: Math.max(width, sheet.textX + dv.widest * 8.2 + 24)
                contentHeight: dv.rows.length * dv.lineH + 8
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                    width: view.contentWidth
                    Repeater {
                        model: dv.rows
                        delegate: Item {
                            id: line
                            required property var modelData
                            width: view.contentWidth
                            height: dv.lineH
                            readonly property bool add: modelData.kind === "add"
                            readonly property bool del: modelData.kind === "del"

                            Rectangle {
                                anchors.fill: parent
                                color: line.add ? Qt.alpha(dv.cAdd, 0.16)
                                     : line.del ? Qt.alpha(dv.cDel, 0.15) : "transparent"
                            }
                            Text {
                                x: 0
                                width: sheet.numW
                                height: parent.height
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                text: line.modelData.o > 0 ? line.modelData.o : ""
                                font.family: w.fontFamily
                                font.pixelSize: 11
                                color: w.cSub
                                opacity: 0.55
                            }
                            Text {
                                x: sheet.numW + 6
                                width: sheet.numW
                                height: parent.height
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                text: line.modelData.n > 0 ? line.modelData.n : ""
                                font.family: w.fontFamily
                                font.pixelSize: 11
                                color: w.cSub
                                opacity: 0.55
                            }
                            Text {
                                x: sheet.signX
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: line.add ? "+" : line.del ? "−" : " "
                                font.family: w.fontFamily
                                font.pixelSize: 13
                                color: line.add ? dv.cAdd : dv.cDel
                            }
                            Text {
                                x: sheet.textX
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.PlainText
                                text: line.modelData.text.length ? line.modelData.text : " "
                                font.family: w.fontFamily
                                font.pixelSize: 13
                                color: line.add ? w.cText : line.del ? Qt.alpha(w.cText, 0.8) : Qt.alpha(w.cText, 0.6)
                            }
                        }
                    }
                }
            }

            // a scrollbar, drawn rather than imported
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 4
                radius: 2
                visible: view.contentHeight > view.height + 1
                color: Qt.alpha(w.cText, 0.25)
                height: Math.max(26, view.height * view.height / Math.max(1, view.contentHeight))
                y: (view.height - height) * (view.contentHeight > view.height
                     ? Math.max(0, Math.min(1, view.contentY / (view.contentHeight - view.height))) : 0)
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            text: "↑↓ scroll   ·   tab / shift+tab jump to the next change   ·   esc back"
            font.family: w.fontFamily
            font.pixelSize: 11
            color: w.cSub
            opacity: 0.6
        }
    }

    // the longest line decides how far sideways it can go
    readonly property int widest: {
        var n = 0;
        for (var i = 0; i < dv.rows.length; i++) n = Math.max(n, dv.rows[i].text.length);
        return Math.min(n, 400);
    }

    Keys.onPressed: function(e) {
        e.accepted = true;
        var page = Math.max(dv.lineH, view.height - dv.lineH * 2);
        var bottom = Math.max(0, view.contentHeight - view.height);
        if (e.key === Qt.Key_Escape || (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_D)) dv.close();
        else if (e.key === Qt.Key_Tab) dv.jump(1);
        else if (e.key === Qt.Key_Backtab) dv.jump(-1);
        else if (e.key === Qt.Key_Down) view.contentY = Math.min(bottom, view.contentY + dv.lineH * 2);
        else if (e.key === Qt.Key_Up) view.contentY = Math.max(0, view.contentY - dv.lineH * 2);
        else if (e.key === Qt.Key_Right) view.contentX = Math.min(Math.max(0, view.contentWidth - view.width), view.contentX + 40);
        else if (e.key === Qt.Key_Left) view.contentX = Math.max(0, view.contentX - 40);
        else if (e.key === Qt.Key_PageDown) view.contentY = Math.min(bottom, view.contentY + page);
        else if (e.key === Qt.Key_PageUp) view.contentY = Math.max(0, view.contentY - page);
        else if (e.key === Qt.Key_Home) view.contentY = 0;
        else if (e.key === Qt.Key_End) view.contentY = bottom;
    }
}
