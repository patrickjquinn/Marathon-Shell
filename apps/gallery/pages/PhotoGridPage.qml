import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Gallery 1.0
import "../GalleryModel.js" as Model

Page {
    id: root

    property var store
    // "all", "album" or "memory"
    property string kind: "all"
    property string albumId
    property int memoryYears
    property string title
    property bool searching: false
    property string query

    readonly property var photos: kind === "album" ? Model.albumPhotos(store.photos, albumId)
                                : kind === "memory" ? Model.memoryPhotos(store.memories, memoryYears)
                                : store.photos
    readonly property var shown: searching ? Model.filter(photos, query) : photos

    function openPhoto(index) {
        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"),
                       { store: root.store, photos: root.shown, currentIndex: index });
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
                description: root.photos.length === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(root.photos.length)
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
            source: modelData.thumbnailPath || modelData.path
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Model.fileName(modelData)
            Accessible.onPressAction: root.openPhoto(index)
            Keys.onReturnPressed: root.openPhoto(index)
            Keys.onEnterPressed: root.openPhoto(index)
            Keys.onSpacePressed: root.openPhoto(index)
            onClicked: root.openPhoto(index)

            FocusFrame { parent: thumb }
        }

        ViewPlaceholder {
            enabled: grid.count === 0
            text: root.searching && root.photos.length > 0 ? qsTr("No matching photos") : qsTr("No photos")
            hintText: root.searching && root.photos.length > 0 ? qsTr("Try a different name, album or date") : ""
        }

        VerticalScrollDecorator {}
    }
}
