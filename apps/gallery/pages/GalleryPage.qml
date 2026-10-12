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
        if (row.kind === "memory")
            return row.years === 1 ? qsTr("A year ago") : qsTr("%1 years ago").arg(row.years);
        return row.name;
    }

    function rowDetail(row) {
        const parts = [row.count === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(row.count)];
        if (row.videoCount > 0)
            parts.push(row.videoCount === 1 ? qsTr("1 video") : qsTr("%1 videos").arg(row.videoCount));
        return parts.join(" · ");
    }

    SilicaListView {
        id: list

        objectName: "collections"
        anchors.fill: parent
        model: Model.collections(root.store.photos, root.store.albums, root.store.memories)
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

            contentHeight: Theme.itemSizeExtraLarge
            enabled: modelData.count > 0
            Accessible.name: root.rowTitle(modelData) + ", " + root.rowDetail(modelData)
            onClicked: root.open(modelData)

            Image {
                id: thumb

                width: Theme.itemSizeExtraLarge
                height: width
                source: row.modelData.cover ? (row.modelData.cover.thumbnailPath || row.modelData.cover.path) : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true

                Rectangle {
                    anchors.fill: parent
                    visible: thumb.status !== Image.Ready
                    color: Theme.rgba(Theme.primaryColor, 0.1)
                }
            }

            Column {
                anchors.left: thumb.right
                anchors.leftMargin: Theme.paddingLarge
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: root.rowTitle(row.modelData)
                    truncationMode: TruncationMode.Fade
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: root.rowDetail(row.modelData)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: list.count === 0
            text: root.store.scanning ? qsTr("Looking for photos") : qsTr("No photos yet")
            hintText: root.store.scanning ? qsTr("Scanning your Pictures and DCIM folders")
                                          : qsTr("Take photos with Camera, or copy images into your Pictures folder")
        }

        VerticalScrollDecorator {}
    }
}
