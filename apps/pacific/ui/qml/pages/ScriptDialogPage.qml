// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A page's alert, confirm, prompt or "leave this page?" dialog. The page
// is named, so a dialog cannot pretend to come from Pacific.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific.WebView 1.0

Dialog {
    id: dialog

    property var request
    property string origin
    property bool _answered: false

    allowedOrientations: Orientation.All

    onAccepted: {
        _answered = true
        request.accept(request.type === ScriptDialog.Prompt ? input.text : "")
    }
    onRejected: {
        if (!_answered)
            request.reject()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            DialogHeader {
                title: dialog.request && dialog.request.type === ScriptDialog.BeforeUnload ? qsTr("Leave this page?") : qsTr("%1 says").arg(dialog.origin)
                acceptText: dialog.request && dialog.request.type === ScriptDialog.BeforeUnload ? qsTr("Leave") : qsTr("OK")
                cancelText: dialog.request && dialog.request.type === ScriptDialog.Alert ? "" : qsTr("Cancel")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dialog.request ? dialog.request.message.substring(0, 2000) : ""
                color: Theme.highlightColor
            }
            TextField {
                id: input
                width: parent.width
                visible: dialog.request && dialog.request.type === ScriptDialog.Prompt
                text: dialog.request ? dialog.request.defaultText : ""
                label: qsTr("Answer")
                placeholderText: qsTr("Answer")
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
        VerticalScrollDecorator {}
    }
}
