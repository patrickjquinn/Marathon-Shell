import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation
import "TouchTarget.js" as TouchTarget

S.Button {
    id: root

    activeFocusOnTab: true

    // The hit area reaches the 7 mm minimum without the control growing.
    readonly property real _panelDpi: typeof DeviceProfile !== "undefined" && DeviceProfile.panelDpi ? DeviceProfile.panelDpi : 0
    readonly property real _hitPadX: TouchTarget.pad(width, _panelDpi, Screen.pixelDensity)
    readonly property real _hitPadY: TouchTarget.pad(height, _panelDpi, Screen.pixelDensity)
    containmentMask: Item {
        parent: root
        x: -root._hitPadX
        y: -root._hitPadY
        width: root.width + 2 * root._hitPadX
        height: root.height + 2 * root._hitPadY
    }
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: root.clicked(null)
    Keys.onPressed: function (event) {
        if (root.enabled && Activation.isActivationKey(event)) {
            event.accepted = true;
            root.clicked(null);
        }
    }

    FocusFrame {
        parent: root
    }
}
