import MarathonApp.Gallery
import MarathonApp.Gallery
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property string albumId: ""
    property string albumName: ""
    property var photos: []

    function findParentApp(item) {
        var parent = item.parent;
        while (parent) {
            if (parent.objectName === "galleryApp" || parent.appId === "gallery")
                return parent;

            parent = parent.parent;
        }
        return galleryApp;
    }

    color: MColors.background
    Component.onCompleted: {
        if (typeof MediaLibraryManager !== 'undefined' && albumId)
            Qt.callLater(function () {
                photos = MediaLibraryManager.getPhotos(albumId);
            });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: MColors.elevated
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            z: 100

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.md

                Icon {
                    name: "chevron-left"
                    size: 24
                    color: MColors.textPrimary
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        onClicked: root.StackView.view.pop()
                    }
                }

                Text {
                    text: root.albumName
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.DemiBold
                    font.family: MTypography.fontFamily
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }

        GridView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: width / 3
            cellHeight: cellWidth
            clip: true
            model: photos
            cacheBuffer: cellHeight * 2

            delegate: MCard {
                width: GridView.view.cellWidth - MSpacing.xs
                height: GridView.view.cellHeight - MSpacing.xs
                elevation: 1
                interactive: true
                onClicked: {
                    Logger.info("Gallery", "View photo: " + modelData.id);
                    var app = findParentApp(root);
                    if (app && app.photoViewerLoader) {
                        app.photoViewerLoader.active = true;
                        app.photoViewerLoader.item.show(modelData);
                    }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: Constants.borderWidthThin
                    source: modelData.thumbnailPath || modelData.path
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    clip: true
                    sourceSize.width: Math.round(width)
                    sourceSize.height: Math.round(height)

                    Rectangle {
                        anchors.fill: parent
                        color: MColors.elevated
                        radius: Constants.borderRadiusSharp
                        visible: parent.status === Image.Loading || parent.status === Image.Error

                        Icon {
                            anchors.centerIn: parent
                            name: "image"
                            size: Constants.iconSizeLarge
                            color: MColors.textSecondary
                        }
                    }
                }
            }
        }
    }
}
