// SPDX-FileCopyrightText: 2013 - 2020 Jolla Ltd
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    canAccept: input.text.length > 0

    property alias text: prompt.text
    property alias value: prompt.value
    property alias defaultValue: prompt.defaultValue

    property alias acceptText: prompt.acceptText
    property alias cancelText: prompt.cancelText
    property alias title: prompt.title
    property alias preventDialogsVisible: prompt.preventDialogsVisible
    property alias preventDialogsPrefillValue: prompt.preventDialogsPrefillValue
    property alias preventDialogsValue: prompt.preventDialogsValue

    PromptPopupInterface {
        id: prompt

        anchors.fill: parent
        value: input.text

        onAccepted: dialog.accept()

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: prompt

            TextField {
                id: input

                height: implicitHeight
                width: parent.width
                focus: true
                label: text.length > 0 ? prompt.text : ""
                text: prompt.defaultValue
                placeholderText: prompt.text
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: prompt.accepted()
            }
        }
    }
}
