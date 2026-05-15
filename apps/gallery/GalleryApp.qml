import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Marathon DS · Gallery (screens-apps-2.jsx:GalleryApp).
//
// Display-weight "Gallery" title + search + more. Photos pane is a
// vertical scroll of section bands: each band has an eyebrow
// "DATE · LOCATION" followed by a 3-col thumbnail grid. Memories
// appear as 2-up large cards beneath. Tabs:
// Albums · Photos · Memories · Search.
MApp {
    id: galleryApp

    property var albums: MediaLibraryManager.albums
    property var photos: []
    property string selectedAlbum: ""
    property int currentView: 1            // start on Photos per JSX
    property alias photoViewerLoader: photoViewerLoader

    function refreshAllPhotos() {
        Qt.callLater(function () {
            photos = MediaLibraryManager.getAllPhotos();
        });
    }

    // Group photos into date sections. Falls back to a single "TODAY"
    // section if the model doesn't expose a date.
    function sectionedPhotos() {
        const sections = {};
        const order = [];
        for (let i = 0; i < photos.length; ++i) {
            const p = photos[i];
            const ts = p && p.timestamp ? new Date(p.timestamp) : new Date();
            const now = new Date();
            const diff = now - ts;
            let bucket;
            if (diff < 86400000)
                bucket = "TODAY";
            else if (diff < 86400000 * 2)
                bucket = "YESTERDAY";
            else if (diff < 86400000 * 7)
                bucket = "THIS WEEK";
            else
                bucket = Qt.formatDate(ts, "MMMM yyyy").toUpperCase();
            if (!sections[bucket]) {
                sections[bucket] = [];
                order.push(bucket);
            }
            sections[bucket].push(p);
        }
        return order.map(label => ({
                    label: label,
                    items: sections[label]
                }));
    }

    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        if (MediaLibraryManager.scanLibraryAsync)
            MediaLibraryManager.scanLibraryAsync();
        else
            MediaLibraryManager.scanLibrary();
        refreshAllPhotos();
    }

    Connections {
        function onScanComplete(photoCount, videoCount) {
            Logger.info("Gallery", "Library scan complete: " + photoCount + " photos, " + videoCount + " videos");
            galleryApp.refreshAllPhotos();
        }
        target: MediaLibraryManager
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

            // ── Header — Gallery title + search + more ──────
            MTopBar {
                id: topBar
                width: parent.width
                title: "Gallery"
                actions: [
                    Icon {
                        name: "search"
                        size: 22
                        color: MColors.textSecondary
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10
                            onClicked: HapticService.light()
                        }
                    },
                    Icon {
                        name: "ellipsis-vertical"
                        size: 22
                        color: MColors.textSecondary
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10
                            onClicked: HapticService.light()
                        }
                    }
                ]
            }

            StackLayout {
                width: parent.width
                height: parent.height - topBar.height - tabBar.height
                currentIndex: galleryApp.currentView

                // ── 0: Albums (kept the existing list pattern) ─
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

                    initialItem: ListView {
                        clip: true
                        model: galleryApp.albums
                        spacing: 0
                        delegate: Item {
                            width: ListView.view.width
                            height: 70
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 14
                                anchors.bottomMargin: 14
                                spacing: 12
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 42
                                    height: 42
                                    radius: MRadius.md
                                    color: MColors.elev3
                                    border.width: 1
                                    border.color: MColors.whiteOverlay04
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "image"
                                        size: 18
                                        color: MColors.textSecondary
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 42 - 24 - parent.spacing * 2
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeSubhead
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: modelData.photoCount + " photos"
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                    }
                                }
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "chevron-right"
                                    size: 18
                                    color: MColors.textTertiary
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 16 + 42 + 12
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                height: 1
                                color: MColors.whiteOverlay04
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    albumsStackView.push("pages/AlbumDetailPage.qml", {
                                        "albumId": modelData.id,
                                        "albumName": modelData.name
                                    });
                                }
                            }
                        }
                        MEmptyState {
                            anchors.centerIn: parent
                            visible: galleryApp.albums.length === 0
                            iconName: "folder"
                            iconSize: 64
                            title: "No Albums Yet"
                            message: "Your photo library is empty."
                        }
                    }
                }

                // ── 1: Photos — sectioned 3-col grid (DS layout) ─
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 18
                    topMargin: 8
                    bottomMargin: 16
                    model: galleryApp.sectionedPhotos()

                    delegate: Column {
                        width: ListView.view.width
                        spacing: 8

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            text: modelData.label
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.Bold
                            font.letterSpacing: MTypography.trackingEyebrow
                        }

                        Grid {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            columns: 3
                            spacing: 4

                            property real cellW: (parent.width - 32 - 8) / 3

                            Repeater {
                                model: modelData.items
                                delegate: Rectangle {
                                    width: parent.cellW
                                    height: width
                                    color: MColors.elev2
                                    radius: 2
                                    border.width: 1
                                    border.color: MColors.whiteOverlay04
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        source: modelData.thumbnailPath || modelData.path
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: Math.round(width)
                                        sourceSize.height: Math.round(height)
                                    }

                                    // Video duration badge — top-right when a clip.
                                    Rectangle {
                                        visible: modelData.duration && modelData.duration > 0
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 6
                                        anchors.rightMargin: 6
                                        height: 18
                                        width: durationText.width + 10
                                        radius: 2
                                        color: Qt.rgba(0, 0, 0, 0.6)
                                        Text {
                                            id: durationText
                                            anchors.centerIn: parent
                                            text: {
                                                const s = Math.max(0, modelData.duration || 0);
                                                const m = Math.floor(s / 60);
                                                const ss = Math.floor(s % 60);
                                                return m + ":" + (ss < 10 ? "0" + ss : ss);
                                            }
                                            color: "#FFFFFF"
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeEyebrow
                                            font.weight: Font.Bold
                                            font.features: ({
                                                    "tnum": 1
                                                })
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            HapticService.light();
                                            photoViewerLoader.active = true;
                                            if (photoViewerLoader.item)
                                                photoViewerLoader.item.show(modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MEmptyState {
                        anchors.centerIn: parent
                        visible: galleryApp.photos.length === 0
                        iconName: "image"
                        iconSize: 64
                        title: "No Photos"
                        message: "Your photo library is empty."
                    }
                }

                // ── 2: Memories — placeholder until cluster API lands ─
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    MEmptyState {
                        anchors.centerIn: parent
                        iconName: "sparkles"
                        iconSize: 64
                        title: "No Memories Yet"
                        message: "Memories will appear as your library grows."
                    }
                }

                // ── 3: Search — placeholder ─
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    MEmptyState {
                        anchors.centerIn: parent
                        iconName: "search"
                        iconSize: 64
                        title: "Search Gallery"
                        message: "Search your photos by date, place, or content."
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
                        "icon": "image"
                    },
                    {
                        "label": "Memories",
                        "icon": "sparkles"
                    },
                    {
                        "label": "Search",
                        "icon": "search"
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
