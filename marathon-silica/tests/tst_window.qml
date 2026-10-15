import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Window"
    when: windowShown
    visible: true
    width: 540; height: 960

    property var log: []

    Component {
        id: app
        ApplicationWindow {
            width: 540; height: 960
            initialPage: Component { Page { PageHeader { title: "Notes" } SectionHeader { text: "Today" } Button { objectName: "focusTarget"; y: 300; text: "Go" } } }
        }
    }
    Component {
        id: shortApp
        ApplicationWindow { width: 540; height: 400; initialPage: Component { Page {} } }
    }
    Component { id: page; Page {} }
    Component {
        id: comboPage
        Page {
            property alias combo: combo
            ComboBox {
                id: combo
                width: parent.width
                label: "Repeat"
                menu: ContextMenu { MenuItem { text: "Never" } MenuItem { text: "Daily" } }
            }
        }
    }
    Component {
        id: pulleyApp
        ApplicationWindow {
            width: 540; height: 960
            initialPage: Component {
                Page {
                    SilicaFlickable {
                        objectName: "flick"
                        anchors.fill: parent
                        contentHeight: height
                        PullDownMenu { MenuItem { text: "Refresh" } MenuItem { text: "Settings" } }
                    }
                }
            }
        }
    }
    SignalSpy { id: minimizeSpy; signalName: "minimizeRequested" }
    SignalSpy { id: acceptedSpy; signalName: "accepted" }
    SignalSpy { id: rejectedSpy; signalName: "rejected" }

    function init() { log = []; }

    function test_backPopsPage() {
        const a = createTemporaryObject(app, testCase);
        a.pageStack.push(page, {}, PageStackAction.Immediate);
        compare(a.pageStack.depth, 2);
        verify(a.handleBack());
        tryCompare(a.pageStack, "depth", 1);
    }

    function test_backClosesAnOpenMenuFirst() {
        const a = createTemporaryObject(app, testCase);
        const p = a.pageStack.push(comboPage, {}, PageStackAction.Immediate);
        p.combo.forceActiveFocus();
        keyClick(Qt.Key_Return);
        tryVerify(function () { return p.combo.menu.active; });
        verify(a.handleBack());
        tryVerify(function () { return !p.combo.menu.active; });
        compare(a.pageStack.depth, 2);
    }

    function test_backClosesAPulledDownMenu() {
        const a = createTemporaryObject(pulleyApp, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        tryCompare(a.pageStack.currentPage, "status", PageStatus.Active);
        const flick = findChild(a.pageStack.currentPage, "flick");
        const menu = flick.pullDownMenu;
        tryVerify(function () { return a.pageStack.currentPage.activeFocus; });
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return menu.active; });
        minimizeSpy.target = a;
        minimizeSpy.clear();
        verify(a.handleBack());
        tryVerify(function () { return !menu.active; });
        compare(minimizeSpy.count, 0);
    }

    function test_backOnFirstPageMinimises() {
        const a = createTemporaryObject(app, testCase);
        minimizeSpy.target = a;
        minimizeSpy.clear();
        verify(a.handleBack());
        compare(minimizeSpy.count, 1);
    }

    function test_escapeOnFirstPageIsBack() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        tryVerify(function () { return a.pageStack.currentPage.activeFocus; });
        minimizeSpy.target = a;
        minimizeSpy.clear();
        keyClick(Qt.Key_Escape);
        compare(minimizeSpy.count, 1);
    }

    function test_pageRestoresFocusWhenReturnedTo() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const first = a.pageStack.currentPage;
        const target = findChild(first, "focusTarget");
        target.forceActiveFocus();
        const p = a.pageStack.push(Qt.resolvedUrl("data/TestPage.qml"), {}, PageStackAction.Immediate);
        tryCompare(p, "status", PageStatus.Active);
        a.pageStack.pop(undefined, PageStackAction.Immediate);
        tryCompare(first, "status", PageStatus.Active);
        tryVerify(function () { return target.activeFocus; });
    }

    function test_ctrlMOnPageOpensItsPulley() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const p = a.pageStack.push(Qt.resolvedUrl("data/PulleyPage.qml"), {}, PageStackAction.Immediate);
        tryCompare(p, "status", PageStatus.Active);
        verify(p.activeFocus);
        keyClick(Qt.Key_M, Qt.ControlModifier);
        const view = findChild(p, "view");
        tryVerify(function () { return view.pullDownMenu.active; });
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        tryCompare(p, "log", ["new"]);
    }

    function test_headersAreHeadings() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const header = findChild(a.pageStack.currentPage, "pageHeader");
        verify(header);
        compare(header.Accessible.role, Accessible.Heading);
        compare(header.Accessible.name, "Notes");
        const section = findChild(a.pageStack.currentPage, "sectionHeader");
        compare(section.Accessible.role, Accessible.Heading);
        compare(section.Accessible.name, "Today");
    }

    function openDialog(props) {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const d = a.pageStack.push(Qt.resolvedUrl("data/TestDialog.qml"), props || {}, PageStackAction.Immediate);
        tryCompare(d, "status", PageStatus.Active);
        acceptedSpy.target = d;
        acceptedSpy.clear();
        rejectedSpy.target = d;
        rejectedSpy.clear();
        return { app: a, dialog: d };
    }

    function test_enterAcceptsDialog() {
        const s = openDialog();
        verify(s.dialog.activeFocus);
        keyClick(Qt.Key_Return);
        tryCompare(acceptedSpy, "count", 1);
    }

    function test_enterIgnoredWhenCannotAccept() {
        const s = openDialog({ ok: false });
        keyClick(Qt.Key_Return);
        wait(50);
        compare(acceptedSpy.count, 0);
    }

    function test_pinnedDialogHeaderHidesScrolledContent() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const d = a.pageStack.push(Qt.resolvedUrl("data/ScrollingDialog.qml"), {}, PageStackAction.Immediate);
        tryCompare(d, "status", PageStatus.Active);
        d.flickable.contentY = 400;
        const backdrop = findChild(d.flickable.contentItem, "dialogHeaderBackdrop");
        verify(backdrop, "no backdrop behind the pinned header");
        tryVerify(function () { return backdrop.visible; });
        compare(backdrop.color.a, 1);
        compare(backdrop.mapToItem(d, 0, 0).y, 0);
        d.flickable.contentY = 0;
        verify(!backdrop.visible);
    }

    function find(item, test) {
        if (test(item))
            return item;
        for (let i = 0; i < item.children.length; ++i) {
            const found = find(item.children[i], test);
            if (found)
                return found;
        }
        return null;
    }

    function test_datePickerScrollsToTheLastWeek() {
        const a = createTemporaryObject(shortApp, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const d = a.pageStack.push(Qt.resolvedUrl("data/DatePicker.qml"), {}, PageStackAction.Immediate);
        tryCompare(d, "status", PageStatus.Active);
        const flick = find(d, function (i) { return i.selectedDateText !== undefined; });
        const grid = find(flick.contentItem, function (i) { return i.cellHeight !== undefined && i.weeksVisible !== undefined; });
        verify(grid.y + grid.height > flick.height, "grid fits: the test can't show the bug");
        tryVerify(function () { return flick.contentHeight >= grid.y + grid.height; }, 1000, "last week out of reach");
        flick.contentY = flick.contentHeight - flick.height;
        const backdrop = findChild(flick.contentItem, "dialogHeaderBackdrop");
        verify(backdrop && backdrop.visible, "header band not backed");
    }

    function test_escapeRejectsDialog() {
        const s = openDialog();
        keyClick(Qt.Key_Escape);
        tryCompare(rejectedSpy, "count", 1);
    }

    function test_escapeOnPagePops() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const p = a.pageStack.push(Qt.resolvedUrl("data/TestPage.qml"), {}, PageStackAction.Immediate);
        tryCompare(p, "status", PageStatus.Active);
        verify(p.activeFocus);
        keyClick(Qt.Key_Escape);
        tryCompare(a.pageStack, "depth", 1);
    }
}
