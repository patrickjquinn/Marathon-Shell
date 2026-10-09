// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: one file row of the list pickers (documents, music,
// downloads, files, folders): the MIME type's theme icon, title or file
// name, and size and date.
import QtQuick 2.6
import Sailfish.Silica 1.0

ListItem {
    id: item

    property string itemTitle
    property string itemFileName
    property string itemMimeType
    property real itemSize
    property var itemModified
    property bool itemIsDir
    property bool checked

    contentHeight: Theme.itemSizeMedium
    highlighted: down || checked

    Icon {
        id: icon
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        source: item.itemIsDir ? "image://theme/icon-m-file-folder"
                               : Theme.iconForMimeType(item.itemMimeType)
    }

    Column {
        anchors {
            left: icon.right
            leftMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        Label {
            width: parent.width
            text: item.itemTitle.length > 0 ? item.itemTitle : item.itemFileName
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            visible: !item.itemIsDir
            text: (item.itemTitle.length > 0 && item.itemTitle !== item.itemFileName ? item.itemFileName + " · " : "")
                  + Format.formatFileSize(item.itemSize)
                  + (item.itemModified ? " · " + Format.formatDate(item.itemModified, Formatter.TimepointRelative) : "")
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
}
