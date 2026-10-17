import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "HubWeather"
    when: windowShown

    Window {
        id: window

        width: 720
        height: 720
        visible: true

        MarathonHub {
            id: hub

            anchors.fill: parent
        }
    }

    function card() {
        return findChild(hub, "weatherSummary").parent.parent;
    }

    function sheet() {
        return findChild(hub, "weatherFlick").parent;
    }

    // A new forecast grows the list's header; a tap while it moves only stops it.
    function settle() {
        const list = findChild(hub, "hubList");
        wait(50);
        tryVerify(() => !list.moving && !list.flicking);
        wait(MMotion.moderate + 50);
    }

    function init() {
        WeatherClient.forecast = {};
        WeatherClient.state = "";
        WeatherClient.calls = [];
        NotificationModel.clear();
        sheet().open = false;
        sheet().choosing = false;
        card().expanded = false;
    }

    function test_hiddenWithoutTheService() {
        verify(!card().visible);
    }

    function test_asksForTheWeather() {
        hub.visible = false;
        hub.visible = true;
        verify(WeatherClient.calls.indexOf("refresh") >= 0);
    }

    function test_showsNow() {
        WeatherClient.forecast = WeatherClient.sample();
        tryVerify(() => card().visible);
        const summary = findChild(hub, "weatherSummary");
        verify(summary.height > 0);
        verify(!findChild(hub, "hubHourlyChart").parent.parent.visible);
    }

    function test_caretShowsTheComingHours() {
        WeatherClient.forecast = WeatherClient.sample();
        const caret = findChild(hub, "weatherCaret");
        tryVerify(() => caret.visible && caret.width > 0);
        settle();
        mouseClick(caret);
        tryVerify(() => card().expanded);
        const chart = findChild(hub, "hubHourlyChart");
        compare(chart.hours.length, 6);
        tryVerify(() => chart.parent.parent.height > 0);
    }

    function test_tapOpensTheSheetAndBackClosesIt() {
        WeatherClient.forecast = WeatherClient.sample();
        settle();
        mouseClick(findChild(hub, "weatherSummary"));
        tryVerify(() => sheet().open);
        verify(hub.overlayOpen);
        compare(findChild(hub, "heroTemperature").text, "2°");
        verify(hub.closeOverlay());
        verify(!sheet().open);
        verify(!hub.closeOverlay());
    }

    function test_choosingAPlace() {
        WeatherClient.forecast = WeatherClient.sample();
        sheet().open = true;
        sheet().choosing = true;
        WeatherClient.searchFinished([{ name: "Oulu", region: "North Ostrobothnia, Finland", latitude: 65.01, longitude: 25.47 }], "");
        const field = findChild(hub, "weatherSearch");
        verify(field.visible);
        // Back leaves the search first, then the sheet.
        verify(hub.closeOverlay());
        verify(sheet().open && !sheet().choosing);
        verify(hub.closeOverlay());
    }

    function test_noLocationInvitesAChoice() {
        WeatherClient.state = "no-location";
        tryVerify(() => card().visible);
        verify(!findChild(hub, "weatherCaret").visible);
    }

    function test_noLocationOpensTheChooser() {
        WeatherClient.state = "no-location";
        window.requestActivate();
        tryVerify(() => window.active);
        settle();
        mouseClick(findChild(hub, "weatherSummary"));
        tryVerify(() => sheet().open && sheet().choosing);
        tryVerify(() => findChild(hub, "weatherSearch").activeFocus);
    }
}
