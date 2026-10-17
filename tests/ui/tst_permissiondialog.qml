import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "PermissionDialog"
    when: windowShown

    Window {
        id: win

        width: 720
        height: 720
        visible: true

        PermissionDialog {
            id: dialog
        }
    }

    function init() {
        AppStore.names = { "test": "Test Suite" };
        PermissionManager.currentAppId = "test";
        PermissionManager.currentPermissions = ["notifications", "contacts", "alarms", "sensors"];
        PermissionManager.promptActive = true;
        wait(50);
    }

    function cleanup() {
        PermissionManager.promptActive = false;
    }

    function test_everyPermissionHasItsOwnIcon() {
        for (const p of PermissionManager.currentPermissions)
            verify(dialog.permissionIconName(p) !== "shield", p);
    }

    // The last line scrolls into view above the gesture bar, not under it.
    function test_contentEndsAboveTheGestureBar() {
        const flickable = findChild(dialog, "permissionFlickable");
        const bottom = flickable.mapToItem(dialog, 0, flickable.height).y;
        verify(bottom <= dialog.height - Constants.navBarHeight, bottom);
    }
}
