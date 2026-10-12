import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Terminal
import "../cover"

TestCase {
    id: test

    name: "TerminalCover"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component {
        id: engineComponent
        TerminalEngine {}
    }
    Component {
        id: coverComponent
        TerminalCover {}
    }
    SignalSpy { id: newSpy; signalName: "newSessionRequested" }

    function makeCover(lines) {
        const session = createTemporaryObject(engineComponent, test, { lines: lines });
        return createTemporaryObject(coverComponent, test, { session: session });
    }

    function test_showsTheLastThreeLines() {
        const c = makeCover(["one", "two", "$ ls", "file.txt"]);
        compare(findChild(c, "coverLines").count, 3);
        compare(c.lines, ["two", "$ ls", "file.txt"]);
        verify(!findChild(c, "coverPlaceholder").visible);
    }

    function test_refreshPicksUpOutput() {
        const c = makeCover([]);
        verify(findChild(c, "coverPlaceholder").visible);
        c.session.lines = ["$ "];
        c.refresh();
        compare(findChild(c, "coverLines").count, 1);
    }

    function test_noSession() {
        const c = createTemporaryObject(coverComponent, test);
        verify(findChild(c, "coverPlaceholder").visible);
    }

    function test_newSessionAction() {
        const c = makeCover([]);
        newSpy.target = c;
        newSpy.clear();
        findChild(c, "newSessionAction").triggered();
        compare(newSpy.count, 1);
    }
}
