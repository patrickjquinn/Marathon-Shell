import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "PageViewHub"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonPageView {
            id: pages

            anchors.fill: parent
        }
    }

    function test_leavingTheHubClosesTheWeather() {
        pages.jumpToIndex(0);
        const list = findChild(pages, "weatherFlick");
        tryVerify(() => list !== null);
        const sheet = list.parent;
        sheet.open = true;
        verify(pages.hubOverlayOpen);
        pages.navigateToPage(-1);
        verify(!sheet.open);
        verify(!pages.hubOverlayOpen);
    }
}
