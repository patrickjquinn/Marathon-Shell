import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../pages"

TestCase {
    id: testCase

    name: "Alarms"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appStub
        AppStub {}
    }
    Component {
        id: window
        ApplicationWindow {
            id: win
            property var app
            width: 540
            height: 1140
            initialPage: Component {
                Page {
                    TabView {
                        anchors.fill: parent
                        model: ListModel { Component.onCompleted: append({ title: "Alarms", page: alarmsTab }) }
                        sourceProperty: "page"
                    }
                    Component {
                        id: alarmsTab
                        AlarmsTab { app: win.app }
                    }
                }
            }
        }
    }


    function makeTab(alarms) {
        const app = appStub.createObject(testCase, { alarms: alarms });
        const w = createTemporaryObject(window, testCase, { app: app });
        let list = null;
        tryVerify(() => w.pageStack.currentPage !== null);
        tryVerify(() => (list = findChild(w, "alarmList")) !== null, 3000);
        return { app: app, list: list };
    }

    function makeDialog(props) {
        const app = appStub.createObject(testCase);
        const w = createTemporaryObject(window, testCase, { app: app });
        tryVerify(() => w.pageStack.currentPage !== null);
        props.app = app;
        const dialog = w.pageStack.push(Qt.resolvedUrl("../pages/AlarmDialog.qml"), props, PageStackAction.Immediate);
        tryCompare(dialog, "status", PageStatus.Active);
        return { app: app, dialog: dialog };
    }

    function test_listsAlarms() {
        const t = makeTab([{ id: "a", time: "07:30", label: "Gym", enabled: true, repeat: [1, 3] },
                           { id: "b", time: "22:00", label: "", enabled: false, repeat: [] }]);
        tryCompare(t.list, "count", 2);
    }

    function test_placeholderWhenEmpty() {
        const t = makeTab([]);
        compare(t.list.count, 0);
        verify(findChild(t.list, "alarmsPlaceholder").enabled);
    }

    function test_switchToggles() {
        const t = makeTab([{ id: "a", time: "07:30", label: "Gym", enabled: true, repeat: [] }]);
        tryCompare(t.list, "count", 1);
        let sw = null;
        tryVerify(() => (sw = findChild(t.list, "alarmSwitch")) !== null);
        verify(sw.checked);
        sw.clicked(null);
        compare(t.app.calls, [["toggle", "a"]]);
        verify(sw.checked, "the backend, not the click, flips the switch");
    }

    function test_clickEdits() {
        const t = makeTab([{ id: "a", time: "07:30", label: "Gym", enabled: true, repeat: [] }]);
        tryCompare(t.list, "count", 1);
        let item = null;
        tryVerify(() => (item = findChild(t.list, "alarmItem")) !== null);
        item.clicked(null);
        tryCompare(t.app, "calls", [["edit", "a"]]);
    }

    function test_deleteGoesThroughRemorse() {
        const t = makeTab([{ id: "a", time: "07:30", label: "Gym", enabled: true, repeat: [] }]);
        tryCompare(t.list, "count", 1);
        let item = null;
        tryVerify(() => (item = findChild(t.list, "alarmItem")) !== null);
        item.remorseDelete(() => t.app.deleteAlarm("a"), 100);
        compare(t.app.calls, []);
        tryCompare(t.app, "calls", [["delete", "a"]], 3000);
    }

    function test_dialogSavesNewAlarm() {
        const t = makeDialog({ hour: 6, minute: 45 });
        findChild(t.dialog, "labelField").text = "  Run ";
        const days = findChild(t.dialog, "weekdays");
        days.itemAt(0).clicked(null);
        days.itemAt(6).clicked(null);
        compare(t.dialog.repeat, [0, 1]);
        t.dialog.accept();
        tryCompare(t.app, "calls", [["save", "", 6, 45, "Run", [0, 1]]]);
    }

    function test_dialogEditsExisting() {
        const t = makeDialog({ alarmId: "a", hour: 7, minute: 30, label: "Gym", repeat: [3] });
        compare(findChild(t.dialog, "timePicker").hour, 7);
        findChild(t.dialog, "weekdays").itemAt(2).clicked(null);
        compare(t.dialog.repeat, []);
        t.dialog.accept();
        tryCompare(t.app, "calls", [["save", "a", 7, 30, "Gym", []]]);
    }

    function test_dialogRejectDoesNotSave() {
        const t = makeDialog({ hour: 6, minute: 0 });
        t.dialog.reject();
        tryCompare(t.dialog, "status", PageStatus.Inactive);
        compare(t.app.calls, []);
    }
}
