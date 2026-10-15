import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "OOBETimeZone"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonOOBE {
            id: oobe
        }
    }

    function test_automaticTimeZoneSwitch() {
        SettingsManagerCpp.automaticTimeZone = true;
        oobe.currentPage = 3;
        const sw = findChild(oobe, "automaticZoneSwitch");
        verify(sw);
        tryVerify(() => sw.mapToItem(oobe, 0, 0).x === 0);
        verify(sw.checked);
        compare(sw.description, "Europe/Dublin");
        // Below the fold at this scale: the step scrolls to it.
        mouseDrag(oobe, 360, 450, 0, -300);
        const flick = sw.parent.parent.parent;
        tryVerify(() => !flick.moving);
        verify(sw.mapToItem(oobe, 0, sw.height).y < 600);
        mouseClick(sw);
        tryVerify(() => !SettingsManagerCpp.automaticTimeZone);
        verify(!sw.checked);
        mouseClick(sw);
        tryVerify(() => SettingsManagerCpp.automaticTimeZone);
    }
}
