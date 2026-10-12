import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../GalleryModel.js" as Model

CoverBackground {
    id: root

    property var photos: []
    // The photo open full screen; otherwise the cover shows a random one.
    property var photo: null
    property var randomPhoto: null
    readonly property var shownPhoto: photo || randomPhoto

    function advance() {
        randomPhoto = Model.pickRandom(photos, randomPhoto, Math.random());
    }

    onPhotosChanged: if (!randomPhoto || !photos.some(p => p.id === randomPhoto.id)) advance()

    Timer {
        objectName: "advanceTimer"
        interval: 30000
        repeat: true
        running: root.status === Cover.Active && !root.photo && root.photos.length > 1
        onTriggered: root.advance()
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.shownPhoto === null
        text: qsTr("No photos")
        icon.source: "image://theme/icon-l-gallery"
    }

    Rectangle {
        id: polaroid

        objectName: "polaroid"
        visible: root.shownPhoto !== null
        width: root.width - 2 * Theme.paddingLarge
        height: width + Theme.paddingLarge * 2
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.paddingLarge
        rotation: -4
        antialiasing: true
        color: Theme.lightPrimaryColor

        Image {
            objectName: "coverImage"
            x: Theme.paddingSmall
            y: Theme.paddingSmall
            width: parent.width - 2 * Theme.paddingSmall
            height: width
            source: root.shownPhoto ? (root.shownPhoto.thumbnailPath || root.shownPhoto.path) : ""
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            clip: true
        }
    }
}
