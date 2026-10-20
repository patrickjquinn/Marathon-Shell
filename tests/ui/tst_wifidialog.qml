import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "WiFiPasswordDialog"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        WiFiPasswordDialog {
            id: dialog
        }
    }

    SignalSpy {
        id: cancelSpy

        target: dialog
        signalName: "cancelled"
    }

    function init() {
        cancelSpy.clear();
        dialog.show("Home", 80, "WPA2", true);
        wait(50);
    }

    function cleanup() {
        dialog.hide();
        wait(50);
    }

    function test_tapOutsideKeepsThePassword() {
        const field = findChild(dialog, "passwordField");
        field.text = "hunter22";
        mouseClick(win.contentItem, win.width / 2, win.height - 40);
        wait(50);
        verify(dialog.visible);
        compare(field.text, "hunter22");
    }

    function test_cancelWorksWhileConnecting() {
        dialog.showConnecting();
        const cancel = findChild(dialog, "cancelButton");
        verify(cancel.enabled);
        const before = Network.cancelledConnects;
        mouseClick(cancel);
        compare(cancelSpy.count, 1);
        compare(Network.cancelledConnects, before + 1);
    }

    function test_cancelBeforeConnectingLeavesNetworkManagerAlone() {
        const before = Network.cancelledConnects;
        mouseClick(findChild(dialog, "cancelButton"));
        compare(Network.cancelledConnects, before);
    }

    function test_connectingTimesOut() {
        dialog.showConnecting();
        const timer = findChild(dialog, "connectTimeout");
        compare(timer.interval, 30000);
        verify(timer.running);
        const before = Network.cancelledConnects;
        timer.triggered();
        compare(Network.cancelledConnects, before + 1);
        verify(!dialog.isConnecting);
        verify(dialog.errorMessage.length > 0);
    }
}
