// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Add or edit a bookmark or a folder.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0

Dialog {
    id: dialog
    objectName: "bookmarkDialog"

    property int bookmarkId: 0
    property bool folderMode: false
    property string bookmarkTitle
    property string bookmarkUrl
    property int parentFolder: 1
    property int targetFolder: parentFolder
    property string targetFolderTitle: qsTr("Bookmarks")

    allowedOrientations: Orientation.All
    canAccept: titleField.text.trim() !== "" && (folderMode || urlField.text.trim() !== "")

    onAccepted: {
        if (bookmarkId === 0 && folderMode)
            Pacific.addFolder(titleField.text.trim(), parentFolder)
        else if (bookmarkId === 0)
            Pacific.addBookmark(urlField.text.trim(), titleField.text.trim(), targetFolder)
        else
            Pacific.editBookmark(bookmarkId, titleField.text.trim(), folderMode ? "" : urlField.text.trim(), targetFolder)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                title: dialog.folderMode ? (dialog.bookmarkId === 0 ? qsTr("New folder") : qsTr("Edit folder"))
                                         : (dialog.bookmarkId === 0 ? qsTr("Add bookmark") : qsTr("Edit bookmark"))
            }
            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Name")
                text: dialog.bookmarkTitle
                EnterKey.iconSource: dialog.folderMode ? "image://theme/icon-m-enter-accept" : "image://theme/icon-m-enter-next"
                EnterKey.onClicked: dialog.folderMode ? dialog.accept() : urlField.forceActiveFocus()
            }
            TextField {
                id: urlField
                width: parent.width
                visible: !dialog.folderMode
                label: qsTr("Address")
                placeholderText: qsTr("Address")
                text: dialog.bookmarkUrl
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
            ValueButton {
                visible: !dialog.folderMode
                label: qsTr("Folder")
                value: dialog.targetFolderTitle
                onClicked: {
                    var picker = pageStack.push(Qt.resolvedUrl("FolderPickerPage.qml"), { selected: dialog.targetFolder })
                    picker.picked.connect(function(id, title) {
                        dialog.targetFolder = id
                        dialog.targetFolderTitle = title
                    })
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
