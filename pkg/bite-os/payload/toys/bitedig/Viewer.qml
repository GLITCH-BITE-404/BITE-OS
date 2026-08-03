// The embedded viewer.
//
// Kept in its own file on purpose. `import QtWebEngine` is a hard failure when
// the module is absent — it takes the whole window down, not just the view. By
// living here and being pulled in through a Loader only once the engine has
// confirmed the module exists, a machine without it loses this feature and
// nothing else.

import QtQuick
import QtQuick.Controls
import QtWebEngine

Item {
    id: viewer
    property string url: ""
    property alias loading: web.loading
    property real progress: web.loadProgress / 100.0
    signal closed()

    onUrlChanged: {
        if (!url) return
        // Defensive: a bare path would silently become about:blank.
        web.url = /^[a-z]+:\/\//.test(url) ? url
                : (url.charAt(0) === "/" ? "file://" + url : "https://" + url)
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        anchors.topMargin: 34
        backgroundColor: "#04080d"
        // No `profile:` block on purpose. Creating a WebEngineProfile inline is
        // deprecated from Qt 6.9 and prints a warning on every launch; the
        // default QML profile is already off-the-record, which is the only
        // property that actually mattered here — a search toy has no business
        // keeping a browsing history.
        settings.javascriptEnabled: true
        settings.localStorageEnabled: false
        settings.screenCaptureEnabled: false
        onNewWindowRequested: function (req) { req.openIn(web) }   // keep it inside
    }

    // ── a thin chrome bar, so it still reads as bitedig and not a browser ──
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 34
        color: "#04080d"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width
                    height: 1; color: "#132720" }

        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: "◈"
            color: "#00e676"
            font.pixelSize: 13
        }
        Text {
            anchors { left: parent.left; leftMargin: 32; right: closeBtn.left
                      rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: web.url.toString()
            color: "#7e948a"
            font.family: "monospace"; font.pixelSize: 10
            elide: Text.ElideMiddle
        }
        Rectangle {                                   // load progress
            anchors.bottom: parent.bottom
            height: 2
            width: parent.width * viewer.progress
            color: "#00e676"
            visible: web.loading
        }
        Rectangle {
            id: closeBtn
            anchors { right: parent.right; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            width: 58; height: 20; radius: 10
            color: cm.containsMouse ? "#132720" : "transparent"
            border.color: "#2a4a3c"
            Text {
                anchors.centerIn: parent
                text: "esc"
                color: "#7e948a"
                font.family: "monospace"; font.pixelSize: 9
            }
            MouseArea {
                id: cm
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: viewer.closed()
            }
        }
    }
}
