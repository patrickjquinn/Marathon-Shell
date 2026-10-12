import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Tabs"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component {
        id: app
        ApplicationWindow {
            width: 540; height: 960
            initialPage: Component {
                Page {
                    property alias tabs: tabs
                    TabView {
                        id: tabs
                        anchors.fill: parent
                        sourceProperty: "page"
                        model: [
                            { title: "Alarms", page: Qt.resolvedUrl("data/TabPage.qml") },
                            { title: "Clock", page: Qt.resolvedUrl("data/TabPage.qml") },
                            { title: "Timer", page: Qt.resolvedUrl("data/TabPage.qml") }
                        ]
                        header: TabBar { model: tabs.model }
                    }
                }
            }
        }
    }

    function tabsOf(a) {
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const t = a.pageStack.currentPage.tabs;
        tryVerify(function () { return t.tabBarItem !== null && buttons(t.tabBarItem).length === 3; });
        return t;
    }

    function buttons(bar) {
        const found = [];
        function walk(item) {
            for (let i = 0; i < item.children.length; ++i) {
                const c = item.children[i];
                if (c.objectName === "tabButton")
                    found.push(c);
                else
                    walk(c);
            }
        }
        walk(bar);
        found.sort(function (x, y) { return x.tabIndex - y.tabIndex; });
        return found;
    }

    function test_barAndButtonsAreAccessible() {
        const t = tabsOf(createTemporaryObject(app, testCase));
        compare(t.tabBarItem.Accessible.role, Accessible.PageTabList);
        const b = buttons(t.tabBarItem);
        compare(b.length, 3);
        compare(b[1].Accessible.role, Accessible.PageTab);
        compare(b[1].Accessible.name, "Clock");
        verify(b[0].Accessible.selected);
        verify(!b[1].Accessible.selected);
        verify(b[1].activeFocusOnTab);
    }

    function test_enterSelectsTab() {
        const t = tabsOf(createTemporaryObject(app, testCase));
        const b = buttons(t.tabBarItem);
        b[2].forceActiveFocus();
        keyClick(Qt.Key_Return);
        tryCompare(t, "currentIndex", 2);
    }

    function test_arrowsMoveBetweenTabs() {
        const t = tabsOf(createTemporaryObject(app, testCase));
        const b = buttons(t.tabBarItem);
        b[0].forceActiveFocus();
        keyClick(Qt.Key_Right);
        tryCompare(t, "currentIndex", 1);
        tryVerify(function () { return b[1].activeFocus; });
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        tryCompare(t, "currentIndex", 2);
    }

    function test_ctrlTabSwitchesFromContent() {
        const t = tabsOf(createTemporaryObject(app, testCase));
        t.forceActiveFocus();
        keyClick(Qt.Key_Tab, Qt.ControlModifier);
        tryCompare(t, "currentIndex", 1);
        keyClick(Qt.Key_PageUp, Qt.ControlModifier);
        tryCompare(t, "currentIndex", 0);
    }
}
