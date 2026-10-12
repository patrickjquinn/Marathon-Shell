import QtQuick
import Sailfish.Silica as S

S.RemorsePopup {
    id: root

    Accessible.role: Accessible.AlertMessage
    Accessible.name: text

    Shortcut {
        sequence: "Esc"
        enabled: root.pending
        onActivated: root.cancel()
        onActivatedAmbiguously: root.cancel()
    }
}
