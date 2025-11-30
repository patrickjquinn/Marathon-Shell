import QtQuick
import MarathonOS.Shell
import MarathonUI.Core

Rectangle {
    id: photoViewer
    anchors.fill: parent
    color: "#000000"
    visible: false
    z: 2000

    property var photo: null

    function show(photoData) {
        photo = photoData;
        visible = true;
    }

    function hide() {
        visible = false;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (mouse.y > parent.height * 0.1 && mouse.y < parent.height * 0.9) {
                photoViewer.hide();
            }
        }
    }

    Image {
        id: photoImage
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        source: photo ? photo.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true

        PinchArea {
            anchors.fill: parent
            pinch.target: photoImage
            pinch.minimumScale: 0.5
            pinch.maximumScale: 3.0
            pinch.dragAxis: Pinch.XAndYAxis
        }
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.actionBarHeight
        color: "#80000000"

        Row {
            anchors.fill: parent
            anchors.margins: MSpacing.md
            spacing: MSpacing.md

            MIconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "x"
                iconSize: Constants.touchTargetMedium
                onClicked: {
                    photoViewer.hide();
                }
            }

            Item {
                width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2
            }

            MIconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "trash"
                iconSize: Constants.touchTargetMedium
                onClicked: {
                    if (photo && typeof MediaLibraryManager !== 'undefined') {
                        MediaLibraryManager.deletePhoto(photo.id);
                        photoViewer.hide();
                    }
                }
            }
        }
    }
}
