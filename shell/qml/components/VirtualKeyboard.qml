import "../keyboard/Core"
import QtQuick

Item {
    id: keyboardContainer

    property bool keyboardAvailable: true
    property bool active: false
    readonly property real keyboardHeight: marathonKeyboard.implicitHeight

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
        if (active)
            marathonKeyboard.show();
        else
            marathonKeyboard.hide();
    }

    MarathonKeyboard {
        id: marathonKeyboard

        anchors.fill: parent
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
        }
    }

    Binding {
        target: typeof HapticManager !== "undefined" ? HapticManager : null
        property: "enabled"
        value: typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp ? (SettingsManagerCpp.keyboardHapticStrength !== "off" && SettingsManagerCpp.vibrationEnabled) : true
        when: typeof HapticManager !== "undefined" && HapticManager
    }

    Behavior on height {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }
}
