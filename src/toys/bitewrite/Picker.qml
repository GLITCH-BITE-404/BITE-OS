// A list to choose from — snippets in CODE, songs in LYRICS. Type to filter,
// ↑↓ to move, Enter to pick, Esc to back out.

import QtQuick

Item {
    id: pk
    property var w
    property string title: ""
    property string note: ""
    property var items: []          // {title, sub, tag}
    property var shownItems: []
    property bool shown: false
    signal chosen(var item)
    signal cancelled()

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function open(t, list, n) {
        pk.title = t;
        pk.note = n || "";
        pk.items = list || [];
        filter.text = "";
        refilter();
        pk.shown = true;
        filter.forceActiveFocus();
        pop.restart();
    }
    function setItems(list, n) {
        pk.items = list || [];
        pk.note = n || "";
        refilter();
    }
    function close() { pk.shown = false; }

    function refilter() {
        var q = filter.text.toLowerCase().trim();
        pk.shownItems = pk.items.filter(function(it) {
            return !q || (it.title + " " + (it.sub || "") + " " + (it.tag || "")).toLowerCase().indexOf(q) >= 0;
        });
        list.currentIndex = 0;
    }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.45 }
    MouseArea { anchors.fill: parent; onClicked: { pk.close(); pk.cancelled(); } }

    Rectangle {
        id: box
        width: Math.min(parent.width - 60, 620)
        height: Math.min(parent.height - 80, 520)
        anchors.centerIn: parent
        radius: w.radius * 1.6
        color: w.cPage
        border.width: 1
        border.color: Qt.alpha(w.cAccent, 0.35)
        MouseArea { anchors.fill: parent }       // clicks inside don't close

        SequentialAnimation {
            id: pop
            NumberAnimation { target: box; property: "scale"; from: 0.94; to: 1.02; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: box; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutQuint }
        }

        Text {
            id: head
            x: 22; y: 18
            text: pk.title
            font.family: w.fontFamily
            font.pixelSize: 15
            font.letterSpacing: 2
            color: w.cAccent
        }

        Rectangle {
            id: field
            x: 18; y: head.y + head.height + 12
            width: parent.width - 36
            height: 36
            radius: w.radius
            color: w.cBase
            TextInput {
                id: filter
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                font.family: w.fontFamily
                font.pixelSize: 14
                color: w.cText
                selectionColor: Qt.alpha(w.cAccent, 0.4)
                onTextEdited: { pk.refilter(); w.sfx.play("key", text.slice(-1)); }
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Down) { list.incrementCurrentIndex(); w.sfx.play("space"); }
                    else if (e.key === Qt.Key_Up) { list.decrementCurrentIndex(); w.sfx.play("space"); }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (pk.shownItems.length) { pk.close(); pk.chosen(pk.shownItems[list.currentIndex]); }
                    } else if (e.key === Qt.Key_Escape) { pk.close(); pk.cancelled(); }
                    else return;
                    e.accepted = true;
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                visible: !filter.text.length
                text: "type to filter…"
                font.family: w.fontFamily
                font.pixelSize: 14
                color: w.cSub
                opacity: 0.5
            }
        }

        ListView {
            id: list
            x: 12; y: field.y + field.height + 10
            width: parent.width - 24
            height: parent.height - y - 40
            clip: true
            model: pk.shownItems
            highlightMoveDuration: 140
            highlight: Rectangle { radius: w.radius; color: Qt.alpha(w.cAccent, 0.18) }
            delegate: Item {
                width: list.width
                height: 54
                Text {
                    x: 12; y: 8
                    width: parent.width - 110
                    elide: Text.ElideRight
                    text: modelData.title
                    font.family: w.fontFamily
                    font.pixelSize: 15
                    color: index === list.currentIndex ? w.cText : Qt.alpha(w.cText, 0.8)
                }
                Text {
                    x: 12; y: 30
                    width: parent.width - 24
                    elide: Text.ElideRight
                    text: modelData.sub || ""
                    font.family: w.fontFamily
                    font.pixelSize: 11
                    color: w.cSub
                    opacity: 0.75
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: 10
                    text: modelData.tag || ""
                    font.family: w.fontFamily
                    font.pixelSize: 11
                    color: w.cAccent
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { pk.close(); pk.chosen(modelData); }
                    hoverEnabled: true
                    onEntered: list.currentIndex = index
                }
            }
        }

        Text {
            anchors.centerIn: list
            visible: !pk.shownItems.length
            width: list.width - 40
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: pk.note || "nothing matches"
            font.family: w.fontFamily
            font.pixelSize: 13
            color: w.cSub
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            text: "↑↓ move   ·   enter pick   ·   esc back"
            font.family: w.fontFamily
            font.pixelSize: 11
            color: w.cSub
            opacity: 0.6
        }
    }
}
