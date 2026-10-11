// BITE-OS: a labelled row of segmented choices (used by the BITE-OS tab's Style section)
import QtQuick
import QtQuick.Layouts
import "../"

RowLayout {
    id: choice
    property var rootObj
    property string label: ""
    property var options: []      // [{ value, text }]
    property string current: ""
    signal picked(string value)
    Layout.fillWidth: true
    spacing: rootObj.s(6)

    Text {
        Layout.preferredWidth: rootObj.s(110)
        text: choice.label
        font.family: ThemeBackend.fontFamily
        font.pixelSize: rootObj.s(12)
        color: ThemeBackend.subtext0
    }

    Repeater {
        model: choice.options
        delegate: Rectangle {
            required property var modelData
            readonly property bool active: choice.current === modelData.value
            Layout.fillWidth: true
            Layout.preferredHeight: rootObj.s(32)
            radius: ThemeBackend.borderRadius
            color: active ? ThemeBackend.mauve : (segMa.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: modelData.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                font.bold: parent.active
                color: parent.active ? ThemeBackend.crust : ThemeBackend.text
            }

            MouseArea {
                id: segMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: choice.picked(modelData.value)
            }
        }
    }
}
