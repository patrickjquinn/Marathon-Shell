// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// HTTP authentication asked by a site (or a proxy).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property var request
    property bool _answered: false

    allowedOrientations: Orientation.All
    canAccept: user.text !== ""

    onAccepted: {
        _answered = true
        request.authenticate(user.text, password.text, false)
    }
    onRejected: if (!_answered) request.cancel()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            DialogHeader {
                title: dialog.request && dialog.request.proxy ? qsTr("Proxy sign-in") : qsTr("Sign in")
                acceptText: qsTr("Sign in")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Theme.highlightColor
                text: dialog.request ? (dialog.request.retry ? qsTr("The name or password was wrong. ") : "")
                                       + qsTr("%1 asks for a name and password (%2).").arg(dialog.request.host).arg(dialog.request.realm) : ""
            }
            TextField {
                id: user
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Name")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: password.forceActiveFocus()
            }
            PasswordField {
                id: password
                width: parent.width
                label: qsTr("Password")
                placeholderText: qsTr("Password")
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
        VerticalScrollDecorator {}
    }
}
