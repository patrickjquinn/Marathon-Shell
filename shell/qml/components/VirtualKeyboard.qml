pragma ComponentBehavior: Bound

import "../keyboard/Core"
import MarathonOS.Shell 1.0
import QtQuick

// Loads MarathonKeyboard asynchronously at startup; loading it on first focus
// lost the first tap on slow devices.
Item {
    id: keyboardContainer

    property bool keyboardAvailable: true
    property bool active: false
    readonly property real keyboardHeight: marathonKeyboardLoader.item ? (marathonKeyboardLoader.item as MarathonKeyboard).implicitHeight : 0

    width: parent ? parent.width : 0
    height: active ? keyboardHeight : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Constants.navBarHeight
    z: Constants.zIndexKeyboard
    visible: active
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "Container active set to: " + active);
        if (active) {
            if (marathonKeyboardLoader.item)
                (marathonKeyboardLoader.item as MarathonKeyboard).show();
        } else if (marathonKeyboardLoader.item) {
            (marathonKeyboardLoader.item as MarathonKeyboard).hide();
        }
    }

    function refreshFieldHints() {
        if (marathonKeyboardLoader.item)
            (marathonKeyboardLoader.item as MarathonKeyboard).refreshFieldHints();
    }

    Loader {
        id: marathonKeyboardLoader

        anchors.fill: parent
        active: true
        asynchronous: true

        sourceComponent: MarathonKeyboard {
            onKeyPressed: function (text) {
                Logger.info("VirtualKeyboard", "Key pressed: " + text);
                InputMethodEngine.commitText(text);
            }
            onBackspace: function () {
                Logger.info("VirtualKeyboard", "Backspace pressed");
                InputMethodEngine.sendBackspace();
            }
            onEnter: function () {
                Logger.info("VirtualKeyboard", "Enter pressed");
                InputMethodEngine.sendEnter();
            }
            onDismissRequested: {
                HapticManager.light();
                keyboardContainer.active = false;
                Logger.info("VirtualKeyboard", "Keyboard dismissed via dismiss button");
            }
            Component.onCompleted: {
                Logger.info("VirtualKeyboard", "MarathonKeyboard created");
                if (keyboardContainer.active)
                    show();
            }
        }
    }

    Binding {
        target: HapticManager
        property: "enabled"
        value: SettingsManagerCpp.keyboardHapticStrength !== "off" && SettingsManagerCpp.vibrationEnabled
    }

    Behavior on height {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }
}
