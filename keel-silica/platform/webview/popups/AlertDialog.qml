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

    property alias text: alert.text

    property alias acceptText: alert.acceptText
    property alias cancelText: alert.cancelText
    property alias title: alert.title
    property alias preventDialogsVisible: alert.preventDialogsVisible
    property alias preventDialogsPrefillValue: alert.preventDialogsPrefillValue
    property alias preventDialogsValue: alert.preventDialogsValue

    AlertPopupInterface {
        id: alert

        anchors.fill: parent

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: alert

            PromptLabel {
                text: alert.text
            }
        }
    }
}
