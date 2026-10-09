// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: one directory of the folder picker page. Sub-folders open a
// further FolderBrowserPage; the pull-down menu selects the folder shown.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page

    property string title
    property string dialogTitle
    property alias path: folderModel.path
    property alias showSystemFiles: folderModel.showSystemFiles
    property var _target: page
    property alias _list: list

    function _select(path) {
        _target._selectPath(path)
    }

    KeelFolderModel {
        id: folderModel
        includeFiles: false
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: folderModel
        header: PageHeader {
            title: page.dialogTitle.length > 0 ? page.dialogTitle : page.title
            description: folderModel.path
        }
        PullDownMenu {
            MenuItem {
                text: qsTr("Select this folder")
                onClicked: page._select(folderModel.path)
            }
        }
        delegate: ContentDelegate {
            required property string fileName
            required property string filePath
            width: ListView.view.width
            itemTitle: fileName
            itemFileName: fileName
            itemIsDir: true
            onClicked: pageStack.push(Qt.resolvedUrl("FolderBrowserPage.qml"), {
                "title": page.title,
                "dialogTitle": page.dialogTitle,
                "path": filePath,
                "showSystemFiles": folderModel.showSystemFiles,
                "_target": page._target
            })
        }
        VerticalScrollDecorator { }
        ViewPlaceholder {
            enabled: folderModel.count === 0
            text: qsTr("No subfolders")
            hintText: qsTr("Pull down to select this folder")
        }
    }
}
