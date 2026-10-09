// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: one directory of the file picker. Folders open a further
// FileBrowserPage on the stack; a file is the pick.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

PickerPageBase {
    id: page

    property alias path: folderModel.path
    property alias nameFilters: folderModel.nameFilters
    property alias showSystemFiles: folderModel.showSystemFiles
    property alias _list: list

    KeelFolderModel {
        id: folderModel
        includeFiles: true
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: folderModel
        header: PageHeader {
            title: page.title
            description: folderModel.path
        }
        delegate: ContentDelegate {
            required property int index
            required property string fileName
            required property string filePath
            required property real fileSize
            required property bool isDir
            required property var lastModified
            required property string mimeType
            width: ListView.view.width
            itemTitle: fileName
            itemFileName: fileName
            itemMimeType: mimeType
            itemSize: fileSize
            itemModified: lastModified
            itemIsDir: isDir
            onClicked: {
                if (isDir) {
                    pageStack.push(Qt.resolvedUrl("FileBrowserPage.qml"), {
                        "title": page.title,
                        "path": filePath,
                        "nameFilters": folderModel.nameFilters,
                        "showSystemFiles": folderModel.showSystemFiles,
                        "_target": page._target
                    })
                } else {
                    page._pick(folderModel.get(index))
                }
            }
        }
        VerticalScrollDecorator { }
        ViewPlaceholder {
            enabled: folderModel.count === 0
            text: qsTr("No files")
        }
    }
}
