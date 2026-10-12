import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// A toolset row: icon and label, left-aligned as in Sailfish Browser.
BackgroundItem {
    id: root

    property alias text: label.text
    property alias iconSource: icon.source

    width: parent ? parent.width : implicitWidth
    height: Theme.itemSizeSmall
    Accessible.name: text

    Icon {
        id: icon

        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        highlighted: root.highlighted
    }
    Label {
        id: label

        anchors {
            left: icon.right
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        truncationMode: TruncationMode.Fade
        color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
}
