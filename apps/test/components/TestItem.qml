import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: root

    property alias text: label.text

    width: parent.width
    Accessible.name: text

    Label {
        id: label

        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        truncationMode: TruncationMode.Fade
        color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
}
