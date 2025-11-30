import QtQuick
import MarathonUI.Theme
import MarathonUI.Core

Column {
    id: root

    property string label: ""
    property string helperText: ""
    property string errorText: ""
    property bool hasError: errorText !== ""
    property alias content: fieldContent.data
    property bool required: false

    spacing: MSpacing.xs
    clip: true

    Accessible.role: Accessible.EditableText
    Accessible.name: label + (required ? " (required)" : "")
    Accessible.description: hasError ? errorText : helperText

    Row {
        width: parent.width
        spacing: MSpacing.xs
        clip: true

        Text {
            text: root.label
            color: root.hasError ? MColors.error : MColors.textSecondary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            font.weight: MTypography.weightMedium
            visible: root.label !== ""
            width: Math.min(implicitWidth, parent.width - (root.required ? 10 : 0))
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }
        }

        Text {
            text: "*"
            color: MColors.error
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            font.weight: MTypography.weightMedium
            visible: root.required
        }
    }

    Item {
        id: fieldContent
        width: parent.width
        height: childrenRect.height
        clip: true
    }

    Text {
        text: root.hasError ? root.errorText : root.helperText
        color: root.hasError ? MColors.error : MColors.textTertiary
        font.pixelSize: MTypography.sizeXSmall
        font.family: MTypography.fontFamily
        font.weight: MTypography.weightNormal
        visible: text !== ""
        width: parent.width
        wrapMode: Text.WordWrap

        Behavior on color {
            ColorAnimation {
                duration: MMotion.sm
            }
        }
    }
}
