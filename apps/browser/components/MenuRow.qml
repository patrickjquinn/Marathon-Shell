import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: root

    property alias text: label.text

    width: parent ? parent.width : implicitWidth
    height: Theme.itemSizeSmall
    Accessible.name: text

    Label {
        id: label

        anchors.centerIn: parent
        color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
}
