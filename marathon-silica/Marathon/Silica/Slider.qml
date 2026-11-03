import QtQuick
import Sailfish.Silica as S

S.Slider {
    id: root

    readonly property real _keyStep: stepSize > 0 ? stepSize : (maximumValue - minimumValue) / 20
    property Item _page

    function _moveTo(v) {
        root.value = Math.max(root.minimumValue, Math.min(root.maximumValue, v));
    }

    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: valueText
    Accessible.onIncreaseAction: root._moveTo(root.value + root._keyStep)
    Accessible.onDecreaseAction: root._moveTo(root.value - root._keyStep)
    onPressedChanged: {
        for (let p = root.parent; root.pressed && !root._page && p; p = p.parent) {
            if (p.hasOwnProperty("backNavigation"))
                root._page = p;
        }
    }
    Keys.onPressed: function (event) {
        if (!root.enabled)
            return;
        const page = (root.maximumValue - root.minimumValue) / 10;
        switch (event.key) {
        case Qt.Key_Right:
        case Qt.Key_Up:
            root._moveTo(root.value + root._keyStep);
            break;
        case Qt.Key_Left:
        case Qt.Key_Down:
            root._moveTo(root.value - root._keyStep);
            break;
        case Qt.Key_PageUp:
            root._moveTo(root.value + page);
            break;
        case Qt.Key_PageDown:
            root._moveTo(root.value - page);
            break;
        case Qt.Key_Home:
            root._moveTo(root.minimumValue);
            break;
        case Qt.Key_End:
            root._moveTo(root.maximumValue);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The page's back swipe looks for a kept grab only once the finger passes
    // its own threshold, so a quick drag crossing that and the slider's in one
    // move went back instead of moving the slider.
    Binding {
        target: root._page
        property: "backNavigation"
        value: false
        when: root.pressed && root._page !== null
    }

    FocusFrame {
        parent: root
    }
}
