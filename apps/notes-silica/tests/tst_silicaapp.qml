import QtQuick
import QtTest
import Sailfish.Silica 1.0
import ".."

TestCase {
    name: "SilicaApp"
    when: windowShown

    Component {
        id: appComponent
        SilicaApp {
            width: 540; height: 1140
            initialPage: Component { Page {} }
        }
    }
    Component { id: pageComponent; Page {} }
    SignalSpy { id: minimizeSpy; signalName: "minimizeRequested" }

    function test_backPopsPage() {
        const app = createTemporaryObject(appComponent, this);
        app.pageStack.push(pageComponent, {}, PageStackAction.Immediate);
        compare(app.pageStack.depth, 2);
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 1);
    }

    function test_backOnFirstPageMinimises() {
        const app = createTemporaryObject(appComponent, this);
        minimizeSpy.target = app;
        minimizeSpy.clear();
        verify(app.handleBack());
        compare(minimizeSpy.count, 1);
        compare(app.pageStack.depth, 1);
    }

}
