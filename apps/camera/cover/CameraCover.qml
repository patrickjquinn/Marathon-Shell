import QtQuick
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property string photo: ""

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.photo === ""
        text: qsTr("No photos")
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
}
