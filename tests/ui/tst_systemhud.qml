import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "SystemHUD"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        SystemHUD {
            id: hud
        }
    }

    function cleanup() {
        UIStore.quickSettingsOpen = false;
        hud.hudVisible = false;
    }

    function test_volumeShowsTheOsd() {
        hud.showVolume(0.4);
        verify(hud.hudVisible);
    }

    // The shade's sliders are the feedback while it is open.
    function test_quietWhileQuickSettingsOpen() {
        UIStore.quickSettingsOpen = true;
        hud.showVolume(0.4);
        verify(!hud.hudVisible);
        hud.showBrightness(0.4);
        verify(!hud.hudVisible);
    }
}
