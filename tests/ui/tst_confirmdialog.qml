import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components/ui"

TestCase {
    id: tc

    name: "ConfirmDialog"
    when: windowShown

    property int confirms: 0

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        ConfirmDialog {
            id: dialog
        }
    }

    function init() {
        confirms = 0;
        dialog.show("Uninstall Notes?", "This app will be removed from your device.", () => confirms++, "Uninstall");
        wait(50);
    }

    function test_verbIsTheTopRightAction() {
        const confirm = findChild(dialog, "confirmButton");
        verify(confirm.x > win.width / 3);
        verify(findChild(dialog, "cancelButton").x < win.width / 3);
        compare(dialog.confirmText, "Uninstall");
        mouseClick(confirm);
        compare(confirms, 1);
        verify(!dialog.shown);
    }

    function test_tapOutsideDoesNotConfirmOrClose() {
        mouseClick(win.contentItem, win.width / 2, win.height - 60);
        verify(dialog.shown);
        compare(confirms, 0);
        dialog.cancel();
        verify(!dialog.shown);
        compare(confirms, 0);
    }
}
