import QtQuick
import Sailfish.Silica as S

S.TextField {
    id: root

    activeFocusOnTab: true
    onActiveFocusChanged: if (activeFocus)
        root._editor.forceActiveFocus()
    Accessible.role: Accessible.EditableText
    Accessible.name: label !== "" ? label : placeholderText
    Accessible.description: description
}
