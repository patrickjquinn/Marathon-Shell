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
        AppModel.names = {
            "test": "Test Suite"
        };
        PermissionManager.currentAppId = "test";
        PermissionManager.currentPermissions = ["notifications", "contacts", "alarms", "sensors"];
        PermissionManager.promptActive = true;
        wait(50);
    }

    function cleanup() {
        PermissionManager.promptActive = false;
        PermissionManager.currentOptions = {};
        PermissionManager.responses = [];
    }

    function ask(appId, permission, options) {
        AppModel.names = {
            "deckard.org.example.cam": "Example Camera"
        };
        PermissionManager.currentAppId = appId;
        PermissionManager.currentPermissions = [permission];
        PermissionManager.currentOptions = options;
        wait(50);
    }

    function test_marathonPromptsHaveNoAndroidChoices() {
        verify(!findChild(dialog, "onceSwitch").visible);
        verify(!findChild(dialog, "preciseSwitch").visible);
        mouseClick(findChild(dialog, "allowButton"));
        compare(PermissionManager.responses[0], [true, false, false]);
    }

    // Android's "only this time" is a choice in the prompt, not a third action.
    function test_onlyThisTime() {
        ask("deckard.org.example.cam", "camera", {
            kind: "foreground",
            once: true
        });
        const once = findChild(dialog, "onceSwitch");
        verify(once.visible);
        verify(!once.checked);
        verify(!findChild(dialog, "preciseSwitch").visible);
        mouseClick(once);
        verify(once.checked);
        mouseClick(findChild(dialog, "allowButton"));
        compare(PermissionManager.responses[0], [true, true, false]);

        ask("deckard.org.example.cam", "microphone", {
            kind: "foreground",
            once: true
        });
        verify(!findChild(dialog, "onceSwitch").checked);
        mouseClick(findChild(dialog, "denyButton"));
        compare(PermissionManager.responses[1], [false, false, false]);
    }

    function test_preciseLocationChoice() {
        ask("deckard.org.example.cam", "location", {
            kind: "foreground",
            once: true,
            accuracy: "choice",
            preciseDefault: true
        });
        const precise = findChild(dialog, "preciseSwitch");
        verify(precise.visible);
        verify(precise.checked);
        const flickable = findChild(dialog, "permissionFlickable");
        flickable.contentY = Math.max(0, flickable.contentHeight - flickable.height);
        wait(50);
        mouseClick(precise);
        mouseClick(findChild(dialog, "allowButton"));
        compare(PermissionManager.responses[0], [true, false, false]);
    }

    function test_whatIsAskedIsSaid() {
        ask("deckard.org.example.cam", "location", {
            kind: "background"
        });
        verify(dialog.descriptionText().indexOf("all the time") >= 0, dialog.descriptionText());
        verify(!findChild(dialog, "onceSwitch").visible);
        ask("deckard.org.example.cam", "location", {
            kind: "precise"
        });
        verify(dialog.descriptionText().indexOf("precise location") >= 0, dialog.descriptionText());
        ask("deckard.org.example.cam", "location", {
            kind: "foreground",
            accuracy: "approximate"
        });
        verify(dialog.descriptionText().indexOf("approximate location") >= 0, dialog.descriptionText());
        ask("deckard.org.example.cam", "camera", {
            kind: "foreground"
        });
        compare(dialog.descriptionText(), "Example Camera is requesting access to camera.");
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
