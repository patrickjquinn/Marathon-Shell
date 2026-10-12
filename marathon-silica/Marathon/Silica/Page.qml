import QtQuick
import Sailfish.Silica as S
import "ViewKeys.js" as ViewKeys

S.Page {
    id: root

    function _stack() {
        for (let p = root.parent; p; p = p.parent) {
            if (p.hasOwnProperty("navigateBack") && p.hasOwnProperty("depth"))
                return p;
        }
        return null;
    }

    property Item _lastFocus

    function _contains(item) {
        for (let p = item; p; p = p.parent) {
            if (p === root)
                return true;
        }
        return false;
    }

    // Coming back to a page puts focus where it was.
    onStatusChanged: {
        if (status !== S.PageStatus.Active)
            return;
        if (_lastFocus && _contains(_lastFocus) && _lastFocus.visible)
            _lastFocus.forceActiveFocus();
        else if (!root.activeFocus)
            root.forceActiveFocus();
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (!root)
                return;
            const item = root.Window.activeFocusItem;
            if (item && item !== root && root._contains(item))
                root._lastFocus = item;
        }
    }
    // With the page itself focused, the menu keys open its view's pulley menu.
    function _pulleyView(item) {
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (child.hasOwnProperty("pullDownMenu") && (child.pullDownMenu || child.pushUpMenu))
                return child;
            const inner = root._pulleyView(child);
            if (inner)
                return inner;
        }
        return null;
    }

    Keys.onPressed: function (event) {
        const view = root._pulleyView(root);
        if (view)
            ViewKeys.openPulley(view, event);
    }

    // The compositor passes Escape to Keel apps; one that no menu or dialog
    // used is the system back.
    Keys.onEscapePressed: function (event) {
        const stack = root._stack();
        if (stack && stack.depth > 1) {
            if (root.backNavigation)
                stack.navigateBack();
        } else if (typeof __silica_applicationwindow_instance !== "undefined" && __silica_applicationwindow_instance
                   && __silica_applicationwindow_instance.handleBack) {
            __silica_applicationwindow_instance.handleBack();
        }
        event.accepted = true;
    }
}
