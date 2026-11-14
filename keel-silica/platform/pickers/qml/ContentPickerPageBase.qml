// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: a single-item picker page over one content category.
import QtQuick 2.6
import Sailfish.Pickers 1.0

PickerPageBase {
    id: page

    property alias _contentType: contentView.contentType
    property alias _model: contentView.model
    property alias _view: contentView

    ContentPickerView {
        id: contentView
        anchors.fill: parent
        headerTitle: page.title
        onPicked: function(props) { page._pick(props) }
    }
}
