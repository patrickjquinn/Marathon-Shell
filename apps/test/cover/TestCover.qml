import QtQuick
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property int passed
    property int failed
    property int triggered

    Column {
        x: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            text: qsTr("Service tests")
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeMedium
            truncationMode: TruncationMode.Fade
        }
        Label {
            objectName: "passedLabel"
            text: qsTr("%1 passed").arg(cover.passed)
            font.pixelSize: Theme.fontSizeLarge
        }
        Label {
            objectName: "failedLabel"
            text: qsTr("%1 failed").arg(cover.failed)
            font.pixelSize: Theme.fontSizeLarge
            color: cover.failed > 0 ? Theme.errorColor : Theme.primaryColor
        }
        Label {
            objectName: "triggeredLabel"
            text: qsTr("%1 triggered").arg(cover.triggered)
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.secondaryColor
        }
    }
}
