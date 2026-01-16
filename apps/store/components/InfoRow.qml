import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: 12

    MLabel {
        text: label + ":"
        width: 100
        variant: "small"
        color: MColors.textSecondary
    }

    MLabel {
        text: value
        width: parent.width - 112
        variant: "small"
        color: MColors.textPrimary
    }
}
