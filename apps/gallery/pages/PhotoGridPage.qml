import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Gallery 1.0
import "../GalleryModel.js" as Model

Page {
    id: root

    property var store
    // "all", "videos", "album" or "memory"
    property string kind: "all"
    property string albumId
    property int memoryYears
    property string title
    property bool searching: false
    property string query

    readonly property var photos: kind === "album" ? Model.albumPhotos(store.photos, albumId)
                                : kind === "memory" ? Model.memoryPhotos(store.memories, memoryYears)
                                : kind === "videos" ? store.videos
                                : Model.merged(store.photos, store.videos)
    readonly property var shown: searching ? Model.filter(photos, query) : photos

    function openPhoto(index) {
        const item = shown[index];
        if (Model.isVideo(item)) {
            pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), { store: root.store, video: item });
            return;
        }
        const stills = shown.filter(p => !Model.isVideo(p));
        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"),
                       { store: root.store, photos: stills, currentIndex: stills.indexOf(item) });
    }


    // Deleting the last photo of an album or memory leaves nothing to show.
    onPhotosChanged: if (photos.length === 0 && kind !== "all" && status === PageStatus.Active) pageStack.pop()

    SilicaGridView {
        id: grid

        readonly property int columns: Math.max(3, Math.floor(width / Theme.itemSizeHuge))

        objectName: "grid"
        anchors.fill: parent
        cellWidth: Math.floor(width / columns)
        cellHeight: cellWidth
        model: root.shown
        header: Column {
            width: grid.width

            PageHeader {
                title: root.title
                description: {
                    const videos = root.photos.filter(Model.isVideo).length;
                    return Model.countText(root.photos.length - videos, videos);
                }
            }
            SearchField {
                id: search

                objectName: "searchField"
                width: parent.width
                visible: root.searching
                placeholderText: qsTr("Search by name, album or date")
                onTextChanged: root.query = text
                onVisibleChanged: if (visible) forceActiveFocus()
            }
        }

        PullDownMenu {
            visible: root.kind === "all"

            MenuItem {
                objectName: "searchAction"
                text: root.searching ? qsTr("Hide search") : qsTr("Search")
                onClicked: {
                    root.searching = !root.searching;
                    if (!root.searching)
                        root.query = "";
                }
            }
        }

        delegate: ThumbnailImage {
            id: thumb

            size: grid.cellWidth
            // Keel's ThumbnailImage fixes its height, which leaves no room for the menu.
            height: implicitHeight
            source: modelData.thumbnailPath || modelData.path
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: (Model.isVideo(modelData) ? qsTr("Video %1") : "%1").arg(Model.fileName(modelData))
            Accessible.onPressAction: root.openPhoto(index)
            Keys.onReturnPressed: root.openPhoto(index)
            Keys.onEnterPressed: root.openPhoto(index)
            Keys.onSpacePressed: root.openPhoto(index)
            onClicked: root.openPhoto(index)
            menu: ContextMenu {
                MenuItem {
                    objectName: "deleteAction"
                    text: qsTr("Delete")
                    onClicked: {
                        const store = root.store;
                        const id = modelData.id;
                        thumb.remorseDelete(function () { store.deletePhoto(id); });
                    }
                }
            }

            // A video given a thumbnail would otherwise pass for a photo.
            Icon {
                objectName: "videoMark"
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    margins: Theme.paddingSmall
                }
                visible: Model.isVideo(modelData) && !!modelData.thumbnailPath
                source: "image://theme/icon-s-video"
                color: Theme.lightPrimaryColor
            }

            FocusFrame { parent: thumb }
        }

        ViewPlaceholder {
            enabled: grid.count === 0
            text: root.searching && root.photos.length > 0 ? qsTr("No matching photos")
                : root.kind === "videos" ? qsTr("No videos") : qsTr("No photos")
            hintText: root.searching && root.photos.length > 0 ? qsTr("Try a different name, album or date") : ""
        }

        VerticalScrollDecorator {}
    }
}
