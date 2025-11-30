import QtQuick
import MarathonOS.Shell
import "../keyboard/Core"

// Virtual Keyboard Container - Marathon Custom Keyboard
Item {
    id: keyboardContainer

    property bool keyboardAvailable: true
    property bool active: false

    // Let keyboard determine its own height dynamically
    readonly property real keyboardHeight: marathonKeyboard.implicitHeight

    width: parent ? parent.width : 0
    height: active ? keyboardHeight : 0

    // DEBUG: Monitor height changes (disabled for performance)
    // onKeyboardHeightChanged: {
    //     Logger.debug("VirtualKeyboard", "keyboardHeight changed: " + keyboardHeight)
    // }
    // onHeightChanged: {
    //     Logger.debug("VirtualKeyboard", "container height changed: " + height)
    // }

    // Proper Qt anchoring - ABOVE nav bar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Constants.navBarHeight  // Position above nav bar

    z: Constants.zIndexKeyboard
    visible: active

    // Watch for external active changes and show/hide keyboard
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "Container active set to: " + active);
        if (active) {
            marathonKeyboard.show();
        } else {
            marathonKeyboard.hide();
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    // Marathon Custom Keyboard (dismiss button integrated into layout)
    MarathonKeyboard {
        id: marathonKeyboard
        anchors.fill: parent

        // Wire to C++ Input Method Engine for proper text input
        onKeyPressed: function (text) {
            Logger.info("VirtualKeyboard", "Key pressed: " + text);
            // Use C++ IME backend for reliable text input
            InputMethodEngine.commitText(text);
        }

        onBackspace: function () {
            Logger.info("VirtualKeyboard", "Backspace pressed");
            // Use C++ IME backend
            InputMethodEngine.sendBackspace();
        }

        onEnter: function () {
            Logger.info("VirtualKeyboard", "Enter pressed");
            // Use C++ IME backend
            InputMethodEngine.sendEnter();
        }

        // Handle dismiss button click from keyboard
        onDismissRequested: {
            HapticService.light();
            keyboardContainer.active = false;
            Logger.info("VirtualKeyboard", "Keyboard dismissed via dismiss button");
        }

        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "MarathonKeyboard created");
        }
    }
}
