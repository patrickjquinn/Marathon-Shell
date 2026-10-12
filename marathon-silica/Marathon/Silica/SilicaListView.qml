import QtQuick
import Sailfish.Silica as S
import "ViewKeys.js" as ViewKeys

S.SilicaListView {
    id: root

    // Silica declares these views against QtQuick 2.0, which predates
    // these properties, so they can only be set by name.
    Binding { target: root; property: "activeFocusOnTab"; value: true }
    Binding { target: root; property: "keyNavigationEnabled"; value: true }

    Accessible.role: Accessible.List
    onActiveFocusChanged: if (activeFocus && currentItem) currentItem.forceActiveFocus()
    onCurrentItemChanged: if (activeFocus && currentItem) currentItem.forceActiveFocus()
    Keys.onPressed: function (event) {
        if (ViewKeys.openPulley(root, event))
            return;
        switch (event.key) {
        case Qt.Key_Home: root.currentIndex = 0; root.positionViewAtBeginning(); break;
        case Qt.Key_End: root.currentIndex = root.count - 1; root.positionViewAtEnd(); break;
        default: return;
        }
        event.accepted = true;
    }
}
