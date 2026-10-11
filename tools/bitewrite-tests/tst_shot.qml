import QtQuick
import QtTest

TestCase {
    name: "shot"
    property var win: null
    function type(t) { for (var i = 0; i < t.length; i++) keyClick(t.charAt(i)); }
    function save(img, file) { img.save(Qt.resolvedUrl(file).toString().replace("file://", "")); }

    function test_shot() {
        var c = Qt.createComponent("Write.qml");
        verify(c.status === Component.Ready, c.errorString());
        win = c.createObject(null);
        win.width = 1400; win.height = 820;
        win.requestActivate();
        tryVerify(function() { return win.ready; }, 5000);
        win.setMode("code");
        wait(300);
        win.newCodeFile();
        wait(200);
        type("html"); keyClick(Qt.Key_Return);
        wait(400);
        type("<h1>line numbers</h1>"); keyClick(Qt.Key_Return);
        type("<p>"); keyClick(Qt.Key_Return);
        type("the gutter follows the caret"); keyClick(Qt.Key_Return);
        type("</p>");
        wait(1500);
        save(grabImage(win.contentItem), "shot-code.png");
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        wait(900);
        keyClick(Qt.Key_Escape);
        wait(400);
        type("<!-- changed -->");
        wait(300);
        keyClick(Qt.Key_D, Qt.ControlModifier);
        wait(300);
        type("ran"); keyClick(Qt.Key_Return);
        wait(700);
        save(grabImage(win.contentItem), "shot-diff.png");
    }
}
