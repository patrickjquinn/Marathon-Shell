import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import Sailfish.Silica as Silica
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "ClipboardManager"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        ClipboardManager {
            id: clipboard
        }
    }

    function init() {
        ClipboardManagerCpp.cleared = false;
        ClipboardManagerCpp.history = [
            {
                "text": "hello",
                "timestamp": 0
            }
        ];
        UIStore.clipboardManagerOpen = true;
        wait(50);
    }

    function test_headerCornerDoesNotClear() {
        mouseClick(win.contentItem, Constants.statusBarHeight, Constants.statusBarHeight + 20);
        verify(!ClipboardManagerCpp.cleared);
    }

    function test_pickingAnEntryCopiesIt() {
        Silica.Clipboard.text = "";
        const entry = findChild(clipboard, "clipEntry");
        mouseClick(entry, 20, entry.height / 2);
        compare(Silica.Clipboard.text, "hello");
        verify(!UIStore.clipboardManagerOpen);
    }

    function test_clearGoesThroughRemorse() {
        findChild(clipboard, "clearHistory").clicked();
        const remorse = findChild(clipboard, "clearRemorse");
        verify(remorse.active);
        verify(!ClipboardManagerCpp.cleared);
        remorse.cancel();
        verify(!ClipboardManagerCpp.cleared);
        findChild(clipboard, "clearHistory").clicked();
        remorse.trigger();
        verify(ClipboardManagerCpp.cleared);
    }
}
