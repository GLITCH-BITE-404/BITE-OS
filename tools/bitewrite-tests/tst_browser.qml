import QtQuick
import QtTest

TestCase {
    id: tc
    name: "browser"
    property var win: null

    function initTestCase() {
        var c = Qt.createComponent("Write.qml");
        verify(c.status === Component.Ready, c.errorString());
        win = c.createObject(null);
        verify(win !== null);
        win.width = 1200; win.height = 800;
        win.requestActivate();
        tryVerify(function() { return win.ready; }, 5000);
    }

    function focusName() {
        var f = win.activeFocusItem;
        return f ? String(f) : "none";
    }

    function openPage() {
        win.setMode("code");
        wait(200);
        win.newCodeFile();                              // the picker, as Ctrl+N opens it
        wait(200);
        var pick = "html";
        for (var k = 0; k < pick.length; k++) keyClick(pick.charAt(k));
        keyClick(Qt.Key_Return);
        wait(300);
        // type a page through the real keyboard path
        var page = "<p>hello</p>";
        for (var i = 0; i < page.length; i++) keyClick(page.charAt(i));
        wait(300);
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryVerify(function() { return focusName().indexOf("Browser") >= 0; }, 3000, "browser never took the keyboard");
    }

    function test_1_blank_chrome_click_keeps_the_browser() {
        openPage();
        // the status line, the empty toolbar end and the empty page: nothing of
        // the browser's own is there, and something of the page's is underneath
        mouseClick(win.contentItem, 600, 787);
        mouseClick(win.contentItem, 1150, 20);
        mouseClick(win.contentItem, 100, 400);
        mouseClick(win.contentItem, 40, 300);         // where the file list is, underneath
        wait(100);
        verify(focusName().indexOf("Browser") >= 0, "focus went to " + focusName());
        compare(win.mode, "code");
        // and Esc still closes it
        keyClick(Qt.Key_Escape);
        wait(400);
        verify(focusName().indexOf("Browser") < 0, "still in the browser after Esc: " + focusName());
        compare(win.mode, "code", "Esc should close the browser, not leave CODE");
    }

    function test_2_a_late_focus_grab_cant_steal_it() {
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryVerify(function() { return focusName().indexOf("Browser") >= 0; }, 3000);
        win.focusPage();                                // what a late callback does
        verify(focusName().indexOf("Browser") >= 0, "focus went to " + focusName());
        keyClick(Qt.Key_Escape);
        wait(400);
        compare(win.mode, "code");
    }
}
