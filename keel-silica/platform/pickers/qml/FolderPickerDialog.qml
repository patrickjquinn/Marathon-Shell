// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 FolderPickerDialog, Keel's clean-room version: a
// dialog for choosing a directory, starting at `path` (home by default).
// Tapping a folder enters it; selectedPath follows the folder shown, so it
// holds the choice when the dialog is accepted. Public API (path,
// selectedPath, title) from the Sailfish.Pickers documentation.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Dialog {
    id: dialog

    property string path: folderModel.homePath
    // Follows the folder shown, so it is current when accepted.
    property string selectedPath: folderModel.path
    property string title
    property alias _list: list

    Component.onCompleted: folderModel.path = path
    onPathChanged: folderModel.path = path

    KeelFolderModel {
        id: folderModel
        includeFiles: false
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
            required property string fileName
            required property string filePath
            width: ListView.view.width
            itemTitle: fileName
            itemFileName: fileName
            itemIsDir: true
            onClicked: folderModel.path = filePath
        }
        VerticalScrollDecorator { }
    }
}
