import QtQuick
import Sailfish.Silica as S

S.Dialog {
    id: root

    onStatusChanged: if (status === S.PageStatus.Active && !root.activeFocus)
        root.forceActiveFocus()
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.canAccept)
                root.accept();
        } else if (event.key === Qt.Key_Escape) {
            root.reject();
        } else {
            return;
        }
        event.accepted = true;
    }
}
