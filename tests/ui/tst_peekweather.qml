import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "PeekWeather"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonPeek {
            id: peek

            anchors.fill: parent
        }

        // Stands in for the nav bar, which sits above the peek.
        MouseArea {
            id: navBar

            property real travelled: 0
            property real startX: 0

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Constants.navBarHeight
            onPressed: mouse => startX = mouse.x
            onPositionChanged: mouse => travelled = startX - mouse.x
        }
    }

    function test_backClosesTheWeatherBeforeThePeek() {
        WeatherClient.forecast = WeatherClient.sample();
        peek.openPeek();
        tryVerify(() => peek.peekProgress >= 0.3);
        const sheet = findChild(peek, "weatherFlick").parent;
        sheet.open = true;
        verify(peek.closeHubOverlay());
        verify(!sheet.open);
        verify(peek.isFullyOpen);
        verify(!peek.closeHubOverlay());
    }

    function test_tapsReachTheHubUnderTheCloseGesture() {
        WeatherClient.forecast = WeatherClient.sample();
        peek.openPeek();
        tryVerify(() => peek.isFullyOpen && peek.peekProgress >= 1);
        const caret = findChild(peek, "weatherCaret");
        tryVerify(() => caret.visible && caret.width > 0);
        // A new forecast grows the list's header; a tap while it moves only stops it.
        const list = findChild(peek, "hubList");
        tryVerify(() => !list.moving && !list.flicking);
        wait(MMotion.moderate + 50);
        const card = findChild(peek, "weatherSummary").parent.parent;
        const was = card.expanded;
        mouseClick(caret);
        tryVerify(() => card.expanded !== was);
    }

    function test_draggingLeftClosesThePeek() {
        peek.openPeek();
        tryVerify(() => peek.isFullyOpen && peek.peekProgress >= 1);
        const x = peek.width - 40, y = peek.height / 2;
        mousePress(peek, x, y);
        for (let i = 1; i <= 20; ++i)
            mouseMove(peek, x - i * peek.width * 0.03, y, 10);
        mouseRelease(peek, x - peek.width * 0.6, y);
        tryVerify(() => !peek.isFullyOpen && peek.peekProgress === 0);
    }

    function test_backSwipeOnTheNavBarPassesThrough() {
        peek.openPeek();
        tryVerify(() => peek.isFullyOpen && peek.peekProgress >= 1);
        navBar.travelled = 0;
        const x = peek.width / 2, y = peek.height - 5;
        mousePress(peek, x, y);
        for (let i = 1; i <= 20; ++i)
            mouseMove(peek, x - i * 15, y, 10);
        mouseRelease(peek, x - 300, y);
        verify(navBar.travelled > 200);
        verify(peek.isFullyOpen);
    }
}
