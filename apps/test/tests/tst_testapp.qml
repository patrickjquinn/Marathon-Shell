import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."
import "../cover"

TestCase {
    id: testCase
    name: "TestApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        TestApp {
            width: 540
            height: 1140
        }
    }
    Component {
        id: coverComponent
        TestCover {}
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
        return app;
    }

    function test_runCountsPassFailTriggeredAndThrow() {
        const app = makeApp();
        compare(app.run("pass", () => true), "passed");
        compare(app.run("effect only", () => undefined), "triggered");
        compare(app.run("not a check", () => 3), "triggered");
        compare(app.run("false", () => false), "failed");
        compare(app.run("throws", () => NoSuchService.call()), "failed");
        compare(app.passedTests, 1);
        compare(app.triggeredTests, 2);
        compare(app.failedTests, 2);
        compare(app.totalTests, 5);
        compare(app.summary, "1 passed · 2 failed · 2 triggered");
    }

    function test_mainPageOpensEveryCategory() {
        const app = makeApp();
        const view = findChild(app.pageStack.currentPage, "categoryView");
        compare(view.count, 6);
        for (let i = 0; i < 6; i++) {
            let item = null;
            tryVerify(() => (item = view.itemAtIndex(i)) !== null);
            mouseClick(item);
            tryCompare(app.pageStack, "depth", 2);
            tryVerify(() => !app.pageStack.busy);
            compare(app.pageStack.currentPage.app, app);
            app.pageStack.pop(undefined, PageStackAction.Immediate);
            tryCompare(app.pageStack, "depth", 1);
        }
    }

    function test_alarmTriggerSignalCounts() {
        const app = makeApp();
        Alarms.alarmTriggered("a1", "Wake up");
        compare(app.passedTests, 1);
    }

    function test_autoRunWithAllServicesPasses() {
        const app = makeApp();
        Location.active = false;
        app.autoRunInterval = 1;
        app.autoRunning = true;
        tryVerify(() => !app.autoRunning, 5000);
        verify(app.totalTests > 20);
        compare(app.failedTests, 0);
        verify(Telephony.calls.some(c => c[0] === "simulateIncomingCall"));
        verify(!Location.active);
    }

    function test_coverShowsCounts() {
        const c = createTemporaryObject(coverComponent, testCase, {
            passed: 4,
            failed: 1,
            triggered: 2
        });
        compare(findChild(c, "passedLabel").text, "4 passed");
        compare(findChild(c, "failedLabel").text, "1 failed");
        compare(findChild(c, "triggeredLabel").text, "2 triggered");
    }
}
