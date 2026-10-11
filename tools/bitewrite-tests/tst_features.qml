import QtQuick
import QtTest

TestCase {
    id: tc
    name: "features"
    property var win: null
    property string data: ""
    property string docs: ""

    function read(path) {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + path, false);
        x.send();
        return x.responseText || "";
    }
    function focusName() { var f = win.activeFocusItem; return f ? String(f) : "none"; }
    function type(t) { for (var i = 0; i < t.length; i++) keyClick(t.charAt(i)); }
    function codeIndex() { try { return JSON.parse(read(data + "/code/index.json")); } catch (e) { return []; } }
    function notesIndex() { try { return JSON.parse(read(data + "/notes/index.json")); } catch (e) { return []; } }
    function names(list) { return list.map(function(f) { return f.name; }).sort().join(","); }

    function initTestCase() {
        var c = Qt.createComponent("Write.qml");
        verify(c.status === Component.Ready, c.errorString());
        win = c.createObject(null);
        win.width = 1300; win.height = 850;
        win.requestActivate();
        tryVerify(function() { return win.ready; }, 5000);
        var o = JSON.parse(read(Qt.resolvedUrl("opts.json").toString().replace("file://", "")));
        data = o.codeDir.replace(/\/code$/, "");
        docs = o.docs;
    }

    function test_1_files_folders_and_line_numbers() {
        keyClick(Qt.Key_F3);
        wait(300);
        type("html"); keyClick(Qt.Key_Return);                       // the blank html page
        wait(300);
        compare(win.codeLang, "html");
        verify(win.gutterW > 0, "no line numbers in CODE");
        type("<p><a href=\"two.html\">two</a></p>");
        keyClick(Qt.Key_Return);
        type("<p>line 2</p>");
        tryVerify(function() { return names(codeIndex()) === "page.html"; }, 3000, names(codeIndex()));

        keyClick(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier);  // a new folder
        wait(200);
        type("site"); keyClick(Qt.Key_Return);
        wait(300);
        type("html"); keyClick(Qt.Key_Return);
        tryVerify(function() { return names(codeIndex()) === "page.html,site/page.html"; }, 3000, names(codeIndex()));

        keyClick(Qt.Key_E, Qt.ControlModifier);                     // rename it
        wait(200);
        type("site/two"); keyClick(Qt.Key_Return);
        tryVerify(function() { return names(codeIndex()) === "page.html,site/two.html"; }, 3000, names(codeIndex()));
        verify(focusName().indexOf("TextEdit") >= 0, "rename didn't give the page back: " + focusName());
        type("<h1>two</h1><a href=\"page.html\">back</a>");
        wait(700);
    }

    function test_2_run_and_browse() {
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryVerify(function() { return focusName().indexOf("Browser") >= 0; }, 3000, "browser didn't open: " + focusName());
        keyClick(Qt.Key_T, Qt.ControlModifier);                     // start page in a new tab
        keyClick(Qt.Key_W, Qt.ControlModifier);                     // and closed again
        verify(focusName().indexOf("Browser") >= 0);
        keyClick(Qt.Key_Escape);
        wait(400);
        verify(focusName().indexOf("TextEdit") >= 0, focusName());
    }

    function test_3_diff() {
        type("<p>added after the run</p>");
        wait(300);
        keyClick(Qt.Key_D, Qt.ControlModifier);
        wait(300);
        type("ran"); keyClick(Qt.Key_Return);                        // "the last time you ran this"
        tryVerify(function() { return focusName().indexOf("Diff") >= 0; }, 3000, "no diff: " + focusName());
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Escape);
        wait(300);
        verify(focusName().indexOf("TextEdit") >= 0, focusName());
    }

    function test_4_install() {
        keyClick(Qt.Key_I, Qt.ControlModifier);
        tryVerify(function() { return read(docs + "/bitewrite/code/site/two.html").indexOf("added after the run") >= 0; },
                  4000, "site/two.html wasn't installed");
    }

    function test_5_notes_folders_and_install_all() {
        keyClick(Qt.Key_F2);
        wait(400);
        verify(win.gutterW === 0, "line numbers leaked into NOTES");
        keyClick(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier);
        wait(200);
        type("ideas"); keyClick(Qt.Key_Return);
        wait(300);
        type("first idea");
        tryVerify(function() {
            return notesIndex().some(function(n) { return n.folder === "ideas" && n.title === "first idea"; });
        }, 3000, JSON.stringify(notesIndex()));
        keyClick(Qt.Key_E, Qt.ControlModifier);
        wait(200);
        type("ideas/deep"); keyClick(Qt.Key_Return);
        tryVerify(function() {
            return notesIndex().some(function(n) { return n.folder === "ideas/deep"; });
        }, 3000, JSON.stringify(notesIndex()));

        keyClick(Qt.Key_I, Qt.ControlModifier | Qt.ShiftModifier);
        tryVerify(function() {
            return read(docs + "/bitewrite/notes/ideas/deep/first idea.txt").indexOf("first idea") >= 0
                && read(docs + "/bitewrite/code/page.html").indexOf("line 2") >= 0;
        }, 4000, "install-all missed something");
    }
}
