import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property string photo: ""

    signal captureRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.photo === ""
        text: qsTr("Camera")
        icon.source: "image://theme/icon-l-camera"
    }

    Image {
        objectName: "coverImage"
        anchors.fill: parent
        visible: cover.photo !== ""
        source: cover.photo
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        clip: true
    }

    // Keeps the cover action legible over a bright photo.
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height / 3
        visible: cover.photo !== ""
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityOverlay) }
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "captureAction"
            iconSource: "image://theme/icon-cover-camera"
            onTriggered: cover.captureRequested()
        }
    }
}
