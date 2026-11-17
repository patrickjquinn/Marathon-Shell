pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.DBus 2.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property var radioState: ({})
    readonly property bool available: radioState.available === true
    readonly property bool playing: radioState.playing === true
    readonly property int frequency: radioState.frequency || lastFrequency.value
    readonly property var stations: radioState.stations || []
    property bool busy: false

    property var lastFrequency: ConfigurationValue {
        key: "/apps/radio/frequency"
        defaultValue: 98000
    }

    function megahertz(khz) {
        return (khz / 1000).toFixed(1);
    }

    function refresh() {
        service.call("GetState", [], state => app.radioState = state);
    }

    function run(method, args) {
        busy = true;
        service.typedCall(method, args, () => app.busy = false, () => {
            app.busy = false;
            app.refresh();
        });
    }

    function play(khz) {
        run("Play", [
            {
                type: "i",
                value: khz
            }
        ]);
    }

    function stop() {
        run("Stop", []);
    }

    function seek(up) {
        run("Seek", [
            {
                type: "b",
                value: up
            }
        ]);
    }

    function scan() {
        run("Scan", []);
    }

    onFrequencyChanged: {
        if (radioState.frequency)
            lastFrequency.value = radioState.frequency;
    }

    appId: "radio"

    DBusInterface {
        id: service

        function stateChanged(state) {
            app.radioState = state;
        }

        service: "org.marathonos.Radio"
        path: "/org/marathonos/Radio"
        iface: "org.marathonos.Radio1"
        signalsEnabled: true
        Component.onCompleted: app.refresh()
    }

    cover: Component {
        RadioCover {
            app: app
        }
    }

    initialPage: Component {
        MainPage {
            app: app
        }
    }
}
