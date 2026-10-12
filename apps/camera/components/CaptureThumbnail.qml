import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: root

    property string source: ""

    width: Theme.itemSizeMedium
    height: width
    Accessible.name: qsTr("Open Gallery")

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityLow)
        visible: root.source === ""

        Icon {
            anchors.centerIn: parent
            source: "image://theme/icon-m-image"
            color: Theme.lightPrimaryColor
        }
    }

    Image {
        objectName: "thumbnailImage"
        anchors.fill: parent
        visible: root.source !== ""
        source: root.source
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        clip: true
        opacity: root.down ? Theme.opacityHigh : 1
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Math.max(1, Math.round(Theme.pixelRatio * 2))
        border.color: Theme.lightPrimaryColor
    }
}
