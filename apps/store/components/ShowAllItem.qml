import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// The "see all" row under a shortened section.
BackgroundItem {
    id: root

    Accessible.role: Accessible.Button
    Accessible.name: label.text

    Label {
        id: label
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("Show all")
        color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
    Icon {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        source: "image://theme/icon-m-right"
        highlighted: root.highlighted
    }
}
