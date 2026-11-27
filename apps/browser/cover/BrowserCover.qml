import QtQuick
import Sailfish.Silica 1.0
import "../BrowserLogic.js" as Logic

CoverBackground {
    id: root

    property string title: ""
    property string url: ""
    property string thumbnail: ""

    signal newTabRequested

    // The page, faint and fading out downwards: the card's frost shows
    // through it, one surface under the title.
    Image {
        id: thumb

        objectName: "coverThumbnail"
        anchors.fill: parent
        visible: root.thumbnail !== ""
        source: root.thumbnail
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        asynchronous: true
        opacity: Theme.opacityFaint
    }
    // Draws the image in its place, so it takes the image's opacity too.
    OpacityRampEffect {
        sourceItem: thumb
        direction: OpacityRamp.TopToBottom
        offset: 0.3
        slope: 1 / 0.7
        opacity: Theme.opacityFaint
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.thumbnail === "" && root.title === ""
        text: qsTr("No page open")
        icon.source: "image://theme/icon-l-browser"
    }

    Column {
        objectName: "coverText"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.title !== ""
        spacing: Theme.paddingSmall

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: root.title
            maximumLineCount: 4
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeExtraSmall
        }
        Label {
            objectName: "coverHost"
            width: parent.width
            text: Logic.displayHost(root.url)
            font.pixelSize: Theme.fontSizeExtraSmall
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
