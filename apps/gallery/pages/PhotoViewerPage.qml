import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: photoViewer

    property var photo: null
    readonly property alias deleteConfirm: deleteConfirm

    function show(photoData) {
        photo = photoData;
        visible = true;
    }

    function hide() {
        deleteConfirm.hide();
        visible = false;
    }

    anchors.fill: parent
    color: MColors.background
    visible: false
    z: 2000

    MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) {
            if (mouse.y > parent.height * 0.1 && mouse.y < parent.height * 0.9)
                photoViewer.hide();
        }
    }

    Image {
        id: photoImage

        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        source: photoViewer.photo ? photoViewer.photo.path : ""
        sourceSize: Qt.size(width, height)
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
        color: MColors.overlayLight

        RowLayout {
            anchors.fill: parent
            anchors.margins: MSpacing.md
            spacing: MSpacing.md

            MIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconName: "x"
                iconSize: Constants.iconSizeLarge
                iconColor: MColors.textPrimary
                a11yName: "Close photo"
                onClicked: photoViewer.hide()
            }

            Item {
                Layout.fillWidth: true
            }

            MIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconName: "trash"
                iconSize: Constants.iconSizeLarge
                iconColor: MColors.textPrimary
                a11yName: "Delete photo"
                visible: photoViewer.photo !== null
                onClicked: deleteConfirm.show()
            }
        }
    }

    MConfirmDialog {
        id: deleteConfirm

        title: "Delete this photo?"
        message: "The photo will be permanently removed from this device."
        confirmText: "Delete photo"
        destructive: true
        onCancelled: hide()
        onConfirmed: {
            MediaLibraryManager.deleteMedia(photoViewer.photo.id);
            photoViewer.hide();
        }
    }
}
