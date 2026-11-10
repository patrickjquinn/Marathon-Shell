// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 MultiFilePickerDialog, Keel's clean-room version:
// selects several files while browsing folders from the home directory;
// `nameFilters` (globs) limit the files shown, and the selection is kept
// across folders. Public API (nameFilters, selectedContent, title, default
// title "Select location") from the Sailfish.Pickers documentation.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Dialog {
    id: dialog

    property string title: qsTr("Select location")
    property alias nameFilters: folderModel.nameFilters
    readonly property alias selectedContent: selection.model
    property alias _folderModel: folderModel
    property alias _list: list

    canAccept: selection.count > 0

    PickerSelection {
        id: selection
    }

    KeelFolderModel {
        id: folderModel
        includeFiles: true
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: folderModel
        header: Column {
            width: parent ? parent.width : 0
            DialogHeader {
                title: dialog.title
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: folderModel.path
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
            }
            ContentDelegate {
                visible: folderModel.canGoUp
                width: parent.width
                itemTitle: ".."
                itemIsDir: true
                onClicked: folderModel.path = folderModel.parentPath
            }
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
            checked: !isDir && selection.contains(filePath)
            onClicked: {
                if (isDir)
                    folderModel.path = filePath
                else
                    selection.toggle(folderModel.get(index))
            }
        }
        VerticalScrollDecorator { }
    }
}
