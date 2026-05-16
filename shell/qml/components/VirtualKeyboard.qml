import "../keyboard/Core"
import MarathonOS.Shell 1.0
import QtQuick

// Wrapper around MarathonKeyboard that defers the actual keyboard QML
// tree until the keyboard is first activated. MarathonKeyboard pulls in
// 6 layout components × ~30 Keys each, the LongPressPopup, the
// LanguageSelector, the prediction bar, and the Dictionary / AutoCorrect
// / EmojiPredictor / PhrasePredictor singletons — about 20-30 MB of
// QML object trees + JS bindings.
//
// Eager instantiation paid that cost at shell start even for users who
// never typed a character (lock screen, glanceable Active Frames, calls
// answered with the touchscreen). By gating MarathonKeyboard behind a
// Loader, the cost only lands the first time an input field gains focus.
Item {
    id: keyboardContainer

    property bool keyboardAvailable: true
    property bool active: false
    readonly property real keyboardHeight: marathonKeyboardLoader.item ? marathonKeyboardLoader.item.implicitHeight : 0

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
            // First activation: load the keyboard tree, then ask it to show
            // after the loader has materialized it on the next frame.
            if (!marathonKeyboardLoader.active) {
                Logger.info("VirtualKeyboard", "Lazy-loading MarathonKeyboard");
                marathonKeyboardLoader.active = true;
            } else if (marathonKeyboardLoader.item) {
                marathonKeyboardLoader.item.show();
            }
        } else if (marathonKeyboardLoader.item) {
            marathonKeyboardLoader.item.hide();
        }
    }

    Loader {
        id: marathonKeyboardLoader

        anchors.fill: parent
        active: false
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
                Logger.info("VirtualKeyboard", "MarathonKeyboard created (lazy)");
                // The container's `active` flipped to true to trigger us
                // loading. Now that we exist, show ourselves.
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
