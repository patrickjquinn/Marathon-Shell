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
}
