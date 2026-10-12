import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

CoverBackground {
    id: cover

    property Calculator calc

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge

        Label {
            objectName: "coverExpression"
            width: parent.width
            horizontalAlignment: Text.AlignRight
            truncationMode: TruncationMode.Fade
            text: cover.calc.expressionText
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
        }
        Label {
            objectName: "coverValue"
            width: parent.width
            horizontalAlignment: Text.AlignRight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeMedium
            wrapMode: cover.calc.errorText !== "" ? Text.Wrap : Text.NoWrap
            text: cover.calc.displayText
            font.pixelSize: Theme.fontSizeExtraLarge
            color: cover.calc.errorText !== "" ? Theme.errorColor : Theme.primaryColor
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
