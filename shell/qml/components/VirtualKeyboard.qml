pragma ComponentBehavior: Bound

import "../keyboard/Core"
import MarathonOS.Shell 1.0
import QtQuick

// Loads MarathonKeyboard asynchronously at startup; loading it on first focus
// lost the first tap on slow devices.
Item {
    id: keyboardContainer

    property bool active: false
    readonly property real keyboardHeight: marathonKeyboardLoader.item ? (marathonKeyboardLoader.item as MarathonKeyboard).implicitHeight : 0
    // 0 down, 1 up; the keys slide, the panel keeps its size.
    property real shown: active ? 1 : 0
    // The app area given up to the keyboard: taken once it is fully up and
    // handed back as it starts down, so apps resize once, not every frame.
    readonly property real reservedHeight: active && shown === 1 ? keyboardHeight : 0

    width: parent ? parent.width : 0
    height: keyboardHeight
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Constants.navBarHeight
    z: Constants.zIndexKeyboard
    visible: shown > 0
    clip: shown < 1
    // The keys stay up until they have slid out.
    onShownChanged: {
        if (shown === 0 && !active && marathonKeyboardLoader.item)
            (marathonKeyboardLoader.item as MarathonKeyboard).hide();
    }
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "Container active set to: " + active);
        if (active && marathonKeyboardLoader.item)
            (marathonKeyboardLoader.item as MarathonKeyboard).show();
        // Apps read the panel's visibility from the input context.
        // qmllint disable missing-property
        if (active && !Qt.inputMethod.visible)
            Qt.inputMethod.show();
        else if (!active && Qt.inputMethod.visible)
            Qt.inputMethod.hide();
        // qmllint enable missing-property
    }

    function refreshFieldHints() {
        if (marathonKeyboardLoader.item)
            (marathonKeyboardLoader.item as MarathonKeyboard).refreshFieldHints();
    }

    Loader {
        id: marathonKeyboardLoader

        width: parent.width
        height: parent.height
        y: (1 - keyboardContainer.shown) * height
        active: true
        asynchronous: true

        sourceComponent: MarathonKeyboard {
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

    Behavior on shown {
        NumberAnimation {
            duration: MMotion.dur(MMotion.normal)
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingDecelerateCurve
        }
    }
}
