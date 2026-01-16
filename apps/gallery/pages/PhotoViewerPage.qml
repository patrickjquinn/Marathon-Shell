import MarathonApp.Gallery
import MarathonApp.Gallery
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: photoViewer

    property var photo: null

    function show(photoData) {
        photo = photoData;
        visible = true;
    }

    function hide() {
        visible = false;
    }

    anchors.fill: parent
    color: "#000000"
    visible: false
    z: 2000

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (mouse.y > parent.height * 0.1 && mouse.y < parent.height * 0.9)
                photoViewer.hide();
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
            pinch.maximumScale: 3
            pinch.dragAxis: Pinch.XAndYAxis
        }
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.actionBarHeight
        color: "#80000000"

        RowLayout {
            anchors.fill: parent
            anchors.margins: MSpacing.md
            spacing: MSpacing.md

            MIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconName: "x"
                iconSize: Constants.iconSizeLarge
                iconColor: "#FFFFFF"
                onClicked: {
                    photoViewer.hide();
                }
            }

            Item {
                Layout.fillWidth: true
            }

            MIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconName: "trash"
                iconSize: Constants.iconSizeLarge
                iconColor: "#FF4444"
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
