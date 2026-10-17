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
}
