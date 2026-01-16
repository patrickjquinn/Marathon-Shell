import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MApp {
    id: galleryApp

    property var albums: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager.albums : []
    property var photos: []
    property string selectedAlbum: ""
    property int currentView: 0
    property alias photoViewerLoader: photoViewerLoader

    function refreshAllPhotos() {
        if (typeof MediaLibraryManager === 'undefined')
            return;

        Qt.callLater(function () {
            photos = MediaLibraryManager.getAllPhotos();
        });
    }

    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        if (typeof MediaLibraryManager !== 'undefined') {
            if (MediaLibraryManager.scanLibraryAsync)
                MediaLibraryManager.scanLibraryAsync();
            else
                MediaLibraryManager.scanLibrary();
        }
    }

    Connections {
        function onScanComplete(photoCount, videoCount) {
            Logger.info("Gallery", "Library scan complete: " + photoCount + " photos, " + videoCount + " videos");
            if (galleryApp.currentView === 1)
                galleryApp.refreshAllPhotos();
        }

        target: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager : null
    }

    Loader {
        id: photoViewerLoader

        anchors.fill: parent
        active: false

        sourceComponent: PhotoViewerPage {}
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            anchors.fill: parent
            spacing: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: galleryApp.currentView

                StackView {
                    id: albumsStackView

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    onDepthChanged: {
                        galleryApp.navigationDepth = depth - 1;
                    }

                    Connections {
                        function onBackPressed() {
                            if (albumsStackView.depth > 1)
                                albumsStackView.pop();
                        }

                        target: galleryApp
                    }

                    pushEnter: Transition {
                        NumberAnimation {
                            property: "x"
                            from: albumsStackView.width
                            to: 0
                            duration: Constants.animationDurationNormal
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            property: "opacity"
                            from: 0.7
                            to: 1
                            duration: Constants.animationDurationNormal
                        }
                    }

                    pushExit: Transition {
                        NumberAnimation {
                            property: "x"
                            from: 0
                            to: -albumsStackView.width * 0.3
                            duration: Constants.animationDurationNormal
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            property: "opacity"
                            from: 1
                            to: 0.7
                            duration: Constants.animationDurationNormal
                        }
                    }

                    popEnter: Transition {
                        NumberAnimation {
                            property: "x"
                            from: -albumsStackView.width * 0.3
                            to: 0
                            duration: Constants.animationDurationNormal
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            property: "opacity"
                            from: 0.7
                            to: 1
                            duration: Constants.animationDurationNormal
                        }
                    }

                    popExit: Transition {
                        NumberAnimation {
                            property: "x"
                            from: 0
                            to: albumsStackView.width
                            duration: Constants.animationDurationNormal
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            property: "opacity"
                            from: 1
                            to: 0.7
                            duration: Constants.animationDurationNormal
                        }
                    }

                    initialItem: ScrollView {
                        contentWidth: width

                        Column {
                            width: parent.width - (MSpacing.md * 2)
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: MSpacing.md

                            Repeater {
                                model: albums

                                MCard {
                                    width: parent.width
                                    height: Constants.touchTargetLarge * 1.5
                                    elevation: 1
                                    interactive: true
                                    onClicked: {
                                        Logger.info("Gallery", "Open album: " + modelData.name);
                                        albumsStackView.push("pages/AlbumDetailPage.qml", {
                                            "albumId": modelData.id,
                                            "albumName": modelData.name
                                        });
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: MSpacing.md
                                        spacing: MSpacing.md

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Constants.touchTargetLarge
                                            height: Constants.touchTargetLarge
                                            radius: Constants.borderRadiusSharp
                                            color: MColors.elevated
                                            border.width: Constants.borderWidthMedium
                                            border.color: MColors.border
                                            antialiasing: Constants.enableAntialiasing

                                            Icon {
                                                anchors.centerIn: parent
                                                name: "image"
                                                size: Constants.iconSizeLarge
                                                color: MColors.accent
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - parent.spacing * 2 - Constants.touchTargetLarge - Constants.iconSizeMedium
                                            spacing: MSpacing.xs

                                            Text {
                                                text: modelData.name
                                                font.pixelSize: MTypography.sizeBody
                                                font.weight: Font.DemiBold
                                                color: MColors.text
                                            }

                                            Text {
                                                text: modelData.photoCount + " photos"
                                                font.pixelSize: MTypography.sizeSmall
                                                color: MColors.textSecondary
                                            }
                                        }

                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "chevron-right"
                                            size: Constants.iconSizeMedium
                                            color: MColors.textTertiary
                                        }
                                    }
                                }
                            }

                            MEmptyState {
                                width: parent.width - parent.padding * 2
                                height: 400
                                visible: albums.length === 0
                                iconName: "folder"
                                iconSize: 96
                                title: "No Albums Yet"
                                message: "Your photo library is empty. Add some photos to see them here!"
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        anchors.fill: parent
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
                                photoViewerLoader.active = true;
                                photoViewerLoader.item.show(modelData);
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

                    MEmptyState {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 400
                        visible: photos.length === 0
                        iconName: "image"
                        iconSize: 96
                        title: "No Photos"
                        message: "No photos found"
                    }
                }
            }

            MTabBar {
                id: tabBar

                width: parent.width
                activeTab: galleryApp.currentView
                tabs: [
                    {
                        "label": "Albums",
                        "icon": "folder"
                    },
                    {
                        "label": "Photos",
                        "icon": "images"
                    }
                ]
                onTabSelected: index => {
                    HapticService.light();
                    galleryApp.currentView = index;
                    if (index === 1 && galleryApp.photos.length === 0)
                        galleryApp.refreshAllPhotos();
                }
            }
        }
    }
}
