import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// Under a list the phone filter shortened: how many it left out, and a tap
// that shows them.
BackgroundItem {
    id: root

    property int count: 0

    objectName: "moreApps"
    visible: count > 0
    height: count > 0 ? Math.max(Theme.itemSizeMedium, content.height + 2 * Theme.paddingMedium) : 0
    Accessible.role: Accessible.Button
    Accessible.name: note.text + ". " + action.text

    Column {
        id: content
        anchors.left: parent.left
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.right: chevron.left
        anchors.rightMargin: Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter

        Label {
            id: note
            width: parent.width
            text: root.count === 1 ? qsTr("1 more app that may not fit a phone screen") : qsTr("%1 more apps that may not fit a phone screen").arg(root.count)
            color: root.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
        }
        Label {
            id: action
            width: parent.width
            text: qsTr("Show all")
            color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
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
