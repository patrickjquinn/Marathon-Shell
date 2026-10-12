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

    // Sailfish Browser's cover is the page itself, full-bleed.
    Image {
        objectName: "coverThumbnail"
        anchors.fill: parent
        visible: root.thumbnail !== ""
        source: root.thumbnail
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        asynchronous: true
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.thumbnail === "" && root.title === ""
        text: qsTr("Browser")
        icon.source: "image://theme/icon-l-browser"
    }

    Column {
        objectName: "coverText"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.thumbnail === "" && root.title !== ""

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: root.title
            maximumLineCount: 3
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

    CoverActionList {
        iconBackground: root.thumbnail !== ""

        CoverAction {
            objectName: "newTabAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: root.newTabRequested()
        }
    }
}
