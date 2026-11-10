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
import "StringUtils.js" as StringUtils

Dialog {
    id: dialog

    property alias text: confirm.text

    property alias acceptText: confirm.acceptText
    property alias cancelText: confirm.cancelText
    property alias thirdButtonText: confirm.thirdButtonText
    property alias title: confirm.title
    property alias preventDialogsVisible: confirm.preventDialogsVisible
    property alias preventDialogsPrefillValue: confirm.preventDialogsPrefillValue
    property alias preventDialogsValue: confirm.preventDialogsValue
    property alias buttonNumClicked: confirm.buttonNumClicked

    ConfirmPopupInterface {
        id: confirm

        anchors.fill: parent

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: confirm

            PromptLabel {
                text: confirm.text
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text.length > 0
                text: StringUtils.geckoKeyToString(confirm.thirdButtonText)
                onClicked: {
                    confirm.buttonNumClicked = 2
                    dialog.reject()
                }
            }
        }
    }
}
