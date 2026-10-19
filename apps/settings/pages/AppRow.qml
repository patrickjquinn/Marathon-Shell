pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// An installed app in a list: icon, name, a subtitle and, when it can go, Uninstall.
ListItem {
    id: item

    property string appId
    property string name
    property string icon
    property string subtitle
    property bool canUninstall

    signal uninstallRequested

    // The menu is gone by the time the remorse timer ends, so the callback lives here.
    function uninstall() {
        remorseDelete(() => item.uninstallRequested());
    }

    objectName: "app-" + appId
    contentHeight: Theme.itemSizeMedium
    Accessible.name: name
    menu: canUninstall ? uninstallMenu : null

    Component {
        id: uninstallMenu

        ContextMenu {
            MenuItem {
                objectName: "uninstallItem"
                text: qsTr("Uninstall")
                onClicked: item.uninstall()
            }
        }
    }

    Image {
        id: icon

        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSizeMedium
        height: Theme.iconSizeMedium
        sourceSize: Qt.size(width, height)
        source: item.icon
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    Icon {
        anchors.centerIn: icon
        visible: icon.status !== Image.Ready
        source: "image://theme/icon-m-apps"
    }
    Column {
        anchors {
            left: icon.right
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: item.name
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            objectName: "subtitle"
            width: parent.width
            visible: text !== ""
            text: item.subtitle
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
}
