import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: root

    property string source: ""
    property bool video

    width: Theme.itemSizeMedium
    height: width
    Accessible.name: source === "" && !video ? qsTr("Open Gallery") : video ? qsTr("Show last video") : qsTr("Show last photo")

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityLow)
        visible: root.source === ""

        Icon {
            anchors.centerIn: parent
            source: root.video ? "image://theme/icon-m-video" : "image://theme/icon-m-image"
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

    Icon {
        objectName: "thumbnailPlay"
        anchors.centerIn: parent
        visible: root.video && root.source !== ""
        source: "image://theme/icon-m-play"
        color: Theme.lightPrimaryColor
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Math.max(1, Math.round(Theme.pixelRatio * 2))
        border.color: Theme.lightPrimaryColor
    }
}
