import QtQuick
import MarathonUI.Core

Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: 12

    MText {
        text: label + ":"
        width: 100
        color: MTheme.onSurfaceVariant
    }

    MText {
        text: value
        width: parent.width - 112
    }
}
