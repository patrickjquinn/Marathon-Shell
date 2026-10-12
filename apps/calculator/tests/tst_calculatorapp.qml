import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "CalculatorApp"
    when: windowShown

    Component { id: appComponent; CalculatorApp { width: 720; height: 1440 } }

    function test_pageAndCoverShareTheCalculator() {
        const app = createTemporaryObject(appComponent, this);
        tryVerify(function () { return app.pageStack.currentPage !== null; });
        compare(app.pageStack.currentPage.calc, app.calc);
        const cover = createTemporaryObject(app.cover, this);
        compare(cover.calc, app.calc);
    }
}
