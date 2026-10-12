import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "CalculatorApp"
    when: windowShown

    Component { id: appComponent; CalculatorApp { width: 720; height: 1440 } }
    Component { id: valueStub; QtObject { property var value } }

    function makeApp(scientific, history) {
        const app = createTemporaryObject(appComponent, this, {
            modeStore: createTemporaryObject(valueStub, this, { value: scientific }),
            historyStore: createTemporaryObject(valueStub, this, { value: history })
        });
        tryVerify(function () { return app.pageStack.currentPage !== null; });
        return app;
    }

    function test_restoresModeAndHistory() {
        const app = makeApp(false, JSON.stringify([{ expression: "1 + 1", result: "= 2" }]));
        verify(!app.pageStack.currentPage.scientific);
        compare(app.calc.history.length, 1);
        compare(app.calc.history[0].result, "= 2");
    }

    function test_savesModeAndHistory() {
        const app = makeApp(true, "[]");
        app.pageStack.currentPage.scientific = false;
        compare(app.modeStore.value, false);
        app.calc.press("2");
        app.calc.press("+");
        app.calc.press("3");
        app.calc.press("=");
        compare(JSON.parse(app.historyStore.value)[0].result, "= 5");
    }

    function test_corruptHistoryIsDropped() {
        const app = makeApp(true, "{oops");
        compare(app.calc.history, []);
        compare(app.historyStore.value, "[]");
    }

    function test_pageAndCoverShareTheCalculator() {
        const app = makeApp(true, "[]");
        compare(app.pageStack.currentPage.calc, app.calc);
        const cover = createTemporaryObject(app.cover, this);
        compare(cover.calc, app.calc);
    }
}
