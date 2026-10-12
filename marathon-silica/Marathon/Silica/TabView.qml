import QtQuick
import Sailfish.Silica.private as P

// Silica's tab view, which Keel keeps private, made public.
P.TabView {
    id: root

    function _step(delta) {
        const n = root.model ? root.model.length !== undefined ? root.model.length : root.model.count : 0;
        if (n > 0)
            root.moveTo((root.currentIndex + delta + n) % n);
    }

    Accessible.role: Accessible.Pane
    Keys.onPressed: function (event) {
        if (!(event.modifiers & Qt.ControlModifier))
            return;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown)
            root._step(1);
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp)
            root._step(-1);
        else
            return;
        event.accepted = true;
    }
}
