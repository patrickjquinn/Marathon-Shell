// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: a multi-item picker dialog over one content category (or
// all four for MultiContentPickerDialog). Tapping toggles an item;
// selectedContent is the ListModel of the selection (fileName, filePath,
// url, title, mimeType), current whenever the dialog is accepted.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Dialog {
    id: dialog

    property string title
    property string acceptText
    readonly property alias selectedContent: selection.model
    property alias _contentType: contentView.contentType
    property alias _model: contentView.model
    property alias _view: contentView

    canAccept: selection.count > 0

    PickerSelection {
        id: selection
    }

    DialogHeader {
        id: header
        title: dialog.title
        acceptText: dialog.acceptText.length > 0 ? dialog.acceptText : defaultAcceptText
    }

    ContentPickerView {
        id: contentView
        anchors {
            fill: parent
            topMargin: header.height
        }
        dialogHeader: header
        selection: selection
        onPicked: function(props) { selection.toggle(props) }
    }
}
