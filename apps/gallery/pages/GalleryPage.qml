import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../GalleryModel.js" as Model

Page {
    id: root

    property var store

    function open(row) {
        const props = { store: root.store, kind: row.kind, title: rowTitle(row) };
        if (row.kind === "album")
            props.albumId = row.albumId;
        else if (row.kind === "memory")
            props.memoryYears = row.years;
        pageStack.push(Qt.resolvedUrl("PhotoGridPage.qml"), props);
    }

    function rowTitle(row) {
        if (row.kind === "all")
            return qsTr("Photos");
        if (row.kind === "videos")
            return qsTr("Videos");
        if (row.kind === "memory")
            return row.years === 1 ? qsTr("A year ago") : qsTr("%1 years ago").arg(row.years);
        return row.name;
    }

    function rowDetail(row) {
        return Model.countText(row.count, row.videoCount || 0);
    }

    SilicaListView {
        id: list

        objectName: "collections"
        anchors.fill: parent
        model: Model.collections(root.store.photos, root.store.videos, root.store.albums, root.store.memories)
        header: PageHeader { title: qsTr("Gallery") }
        section.property: "section"
        section.delegate: SectionHeader {
            required property string section

            text: section === "memories" ? qsTr("Memories") : section === "albums" ? qsTr("Albums") : ""
            visible: text !== ""
            height: visible ? implicitHeight : 0
        }

        delegate: ListItem {
            id: row

            required property var modelData

            contentHeight: Theme.itemSizeLarge
            enabled: modelData.count > 0 || modelData.videoCount > 0
            Accessible.name: root.rowTitle(modelData) + ", " + root.rowDetail(modelData)
            onClicked: root.open(modelData)

            // Jolla Gallery: item count, cover, then the name.
            Label {
                objectName: "rowCount"
                x: Theme.horizontalPageMargin
                width: countMetrics.width
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Number(row.modelData.count + (row.modelData.videoCount || 0)).toLocaleString(Qt.locale(), "f", 0)
                font.pixelSize: Theme.fontSizeLarge
                color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }

            Image {
                id: thumb

                x: Theme.horizontalPageMargin + countMetrics.width + Theme.paddingLarge
                width: Theme.itemSizeLarge
                height: width
                source: row.modelData.cover ? (row.modelData.cover.thumbnailPath || row.modelData.cover.path) : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true

                Icon {
                    anchors.centerIn: parent
                    visible: !row.modelData.cover
                    source: row.modelData.kind === "videos" ? "image://theme/icon-l-video" : "image://theme/icon-l-image"
                    highlighted: row.highlighted
                }
            }

            Label {
                anchors {
                    left: thumb.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: root.rowTitle(row.modelData)
                font.pixelSize: Theme.fontSizeLarge
                truncationMode: TruncationMode.Fade
                color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }

        TextMetrics {
            id: countMetrics

            font.pixelSize: Theme.fontSizeLarge
            text: "00"
        }

        BusyLabel {
            objectName: "busyLabel"
            running: root.store.scanning && list.count === 0
            text: qsTr("Looking for photos")
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: list.count === 0 && !root.store.scanning
            text: qsTr("No photos yet")
            hintText: qsTr("Take photos with Camera, or copy images into your Pictures folder")
        }

        VerticalScrollDecorator {}
    }
}
