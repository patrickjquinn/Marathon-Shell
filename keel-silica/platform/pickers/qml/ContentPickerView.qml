// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the list or grid of one content category, with a search
// field, a busy indicator while the model loads and a placeholder when
// there is nothing to pick. `picked(props)` gives the item's
// selectedContentProperties map; `selection` (a PickerSelection) turns on
// the checked state of the multi pickers.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Item {
    id: view

    property int contentType: KeelContentModel.AnyContent
    property alias model: contentModel
    property string headerTitle
    property bool grid: contentType === KeelContentModel.ImageContent
                        || contentType === KeelContentModel.VideoContent
    property QtObject selection
    property Item dialogHeader
    readonly property var flickable: loader.item

    signal picked(var props)

    KeelContentModel {
        id: contentModel
        contentType: view.contentType
    }

    Component {
        id: headerComponent
        Column {
            width: parent ? parent.width : 0
            PageHeader {
                visible: !view.dialogHeader
                title: view.headerTitle
            }
            SearchField {
                width: parent.width
                placeholderText: qsTr("Search")
                onTextChanged: contentModel.filter = text
                EnterKey.onClicked: focus = false
            }
        }
    }

    Component {
        id: listComponent
        SilicaListView {
            model: contentModel
            header: headerComponent
            section.property: contentModel.contentType === KeelContentModel.AnyContent ? "contentType" : ""
            section.delegate: SectionHeader {
                required property string section
                text: section
            }
            delegate: ContentDelegate {
                required property int index
                required property string fileName
                required property string filePath
                required property real fileSize
                required property var lastModified
                required property string mimeType
                required property string title
                width: ListView.view.width
                itemTitle: title
                itemFileName: fileName
                itemMimeType: mimeType
                itemSize: fileSize
                itemModified: lastModified
                checked: view.selection ? view.selection.contains(filePath) : false
                onClicked: view.picked(contentModel.get(index))
            }
            VerticalScrollDecorator { }
            ViewPlaceholder {
                enabled: contentModel.count === 0 && !contentModel.loading
                text: qsTr("No files")
            }
        }
    }

    Component {
        id: gridComponent
        SilicaGridView {
            id: gridView
            readonly property int columns: width > height ? 6 : 4
            model: contentModel
            header: headerComponent
            cellWidth: Math.floor(width / columns)
            cellHeight: cellWidth
            delegate: ThumbnailDelegate {
                required property int index
                required property string fileName
                required property string filePath
                required property url url
                width: gridView.cellWidth
                height: gridView.cellHeight
                itemUrl: url
                itemFileName: fileName
                isVideo: contentModel.contentType === KeelContentModel.VideoContent
                checked: view.selection ? view.selection.contains(filePath) : false
                onClicked: view.picked(contentModel.get(index))
            }
            VerticalScrollDecorator { }
            ViewPlaceholder {
                enabled: contentModel.count === 0 && !contentModel.loading
                text: contentModel.contentType === KeelContentModel.VideoContent ? qsTr("No videos")
                                                                                   : qsTr("No images")
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: view.grid ? gridComponent : listComponent
    }

    PageBusyIndicator {
        running: contentModel.loading
    }
}
