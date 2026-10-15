import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

CoverBackground {
    id: cover

    property Calculator calc

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            objectName: "coverExpression"
            width: parent.width
            horizontalAlignment: Text.AlignRight
            truncationMode: TruncationMode.Fade
            text: cover.calc.expressionText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Label {
            objectName: "coverValue"
            width: parent.width
            horizontalAlignment: Text.AlignRight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeMedium
            wrapMode: cover.calc.errorText !== "" ? Text.WordWrap : Text.NoWrap
            text: cover.calc.displayText
            font.pixelSize: cover.calc.errorText !== "" ? Theme.fontSizeMedium : Theme.fontSizeHuge
            font.weight: Font.Light
            font.features: ({ "tnum": 1 })
            color: cover.calc.errorText !== "" ? Theme.errorColor : Theme.highlightColor
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "clearAction"
            iconSource: "image://theme/icon-cover-cancel"
            onTriggered: cover.calc.press("C")
        }
    }
}
