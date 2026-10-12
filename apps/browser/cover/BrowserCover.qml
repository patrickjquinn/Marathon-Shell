import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

CoverBackground {
    id: root

    property string title: ""
    property string url: ""
    property string thumbnail: ""

    signal newTabRequested

    Image {
        objectName: "coverThumbnail"
        anchors.fill: parent
        visible: root.thumbnail !== ""
        source: root.thumbnail
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        opacity: Theme.opacityHigh
        asynchronous: true
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.thumbnail === "" && root.title === ""
        text: qsTr("Browser")
        icon.source: "image://theme/icon-l-browser"
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: titleLabel.text !== ""
        height: column.height + Theme.paddingLarge + Theme.itemSizeSmall
        color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)

        Column {
            id: column

            x: Theme.paddingLarge
            y: Theme.paddingMedium
            width: parent.width - 2 * Theme.paddingLarge

            Label {
                id: titleLabel

                objectName: "coverTitle"
                width: parent.width
                text: root.title
                font.pixelSize: Theme.fontSizeMedium
                maximumLineCount: 2
                wrapMode: Text.Wrap
                truncationMode: TruncationMode.Fade
            }
            Label {
                objectName: "coverHost"
                width: parent.width
                text: Logic.displayHost(root.url)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                truncationMode: TruncationMode.Fade
            }
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "newTabAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: root.newTabRequested()
        }
    }
}
