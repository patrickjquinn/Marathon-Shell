import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation
import "pages"

MApp {
    id: galleryApp
    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"

    property var albums: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager.albums : []
    property var photos: []
    property string selectedAlbum: ""
    property int currentView: 0

    Component.onCompleted: {
        if (typeof MediaLibraryManager !== 'undefined') {
            MediaLibraryManager.scanLibrary();
        }
    }

    Connections {
        target: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager : null
        function onScanComplete(photoCount, videoCount) {
            Logger.info("Gallery", "Library scan complete: " + photoCount + " photos, " + videoCount + " videos");
        }
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

                    // Update parent's navigationDepth when stack changes
                    onDepthChanged: {
                        galleryApp.navigationDepth = depth - 1;
                    }

                    // Handle back button
                    Connections {
                        target: galleryApp
                        function onBackPressed() {
                            if (albumsStackView.depth > 1) {
                                albumsStackView.pop();
                            }
                        }
                    }

                    // Transitions
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
                            to: 1.0
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
                            from: 1.0
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
                            to: 1.0
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
                            from: 1.0
                            to: 0.7
                            duration: Constants.animationDurationNormal
                        }
                    }

                    initialItem: ScrollView {
                        contentWidth: width
                        
                        Column {
                            width: parent.width
                            padding: MSpacing.md
                            spacing: MSpacing.md

                            Repeater {
                                model: albums

                                MCard {
                                    width: parent.width - parent.padding * 2
                                    height: Constants.touchTargetLarge * 1.5
                                    elevation: 1
                                    interactive: true

                                    onClicked: {
                                        Logger.info("Gallery", "Open album: " + modelData.name);
                                        albumsStackView.push("pages/AlbumDetailPage.qml", {
                                            albumId: modelData.id,
                                            albumName: modelData.name
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
                        message: selectedAlbum ? "This album is empty" : "Select an album to view photos"
                    }
                }
            }

            MTabBar {
                id: tabBar
                width: parent.width
                activeTab: galleryApp.currentView

                tabs: [
                    {
                        label: "Albums",
                        icon: "folder"
                    },
                    {
                        label: "Photos",
                        icon: "grid"
                    }
                ]

                onTabSelected: index => {
                    HapticService.light();
                    galleryApp.currentView = index;
                }
            }
        }
    }

    property alias photoViewerLoader: photoViewerLoader

    Loader {
        id: photoViewerLoader
        anchors.fill: parent
        active: false
        sourceComponent: PhotoViewerPage {}
    }
}
