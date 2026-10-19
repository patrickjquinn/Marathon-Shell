import QtQuick
import Sailfish.Silica as S
import "Fling.js" as Fling
import "Velocity.js" as Velocity
import "ViewKeys.js" as ViewKeys

S.SilicaFlickable {
    id: root

    flickDeceleration: Fling.deceleration * S.Theme.pixelRatio
    maximumFlickVelocity: Fling.maxVelocity * S.Theme.pixelRatio

    // Fling at the speed the content was moving, not Qt's lagging estimate.
    property var _motion: []
    onDraggingChanged: if (dragging) _motion = []
    onContentXChanged: if (dragging) Velocity.add(_motion, contentX, contentY)
    onContentYChanged: if (dragging) Velocity.add(_motion, contentX, contentY)
    onFlickStarted: {
        const vx = Velocity.rate(_motion, 1);
        const vy = Velocity.rate(_motion, 2);
        if (vx !== 0 || vy !== 0)
            flick(-vx, -vy);
    }

    // A flickable holding controls is not a tab stop itself: Tab goes to the
    // controls, and keys they leave unused scroll it.
    property bool _hasTabStops

    function _findTabStops(item) {
        if (!item || !item.children)
            return false; // contentItem is gone while the flickable is destroyed
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if ((child.activeFocusOnTab && child.visible) || root._findTabStops(child))
                return true;
        }
        return false;
    }

    Component.onCompleted: _hasTabStops = _findTabStops(contentItem)
    onContentHeightChanged: _hasTabStops = _findTabStops(contentItem)

    // Silica declares this view against QtQuick 2.0, which predates
    // activeFocusOnTab, so it can only be set by name.
    Binding { target: root; property: "activeFocusOnTab"; value: !root._hasTabStops }

    Accessible.role: Accessible.Pane
    Keys.onPressed: function (event) {
        if (ViewKeys.openPulley(root, event))
            return;
        const line = S.Theme.itemSizeSmall;
        switch (event.key) {
        case Qt.Key_Down: ViewKeys.scrollTo(root, root.contentY + line); break;
        case Qt.Key_Up: ViewKeys.scrollTo(root, root.contentY - line); break;
        case Qt.Key_PageDown: ViewKeys.scrollTo(root, root.contentY + root.height * 0.9); break;
        case Qt.Key_PageUp: ViewKeys.scrollTo(root, root.contentY - root.height * 0.9); break;
        case Qt.Key_Home: ViewKeys.scrollTo(root, root.originY); break;
        case Qt.Key_End: ViewKeys.scrollTo(root, root.originY + root.contentHeight); break;
        default: return;
        }
        event.accepted = true;
    }
}
