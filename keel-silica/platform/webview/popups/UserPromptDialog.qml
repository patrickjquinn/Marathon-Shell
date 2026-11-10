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

    property alias acceptText: prompt.acceptText
    property alias cancelText: prompt.cancelText
    property alias title: prompt.title
    property alias preventDialogsVisible: prompt.preventDialogsVisible
    property alias preventDialogsPrefillValue: prompt.preventDialogsPrefillValue
    property alias preventDialogsValue: prompt.preventDialogsValue

    UserPromptInterface {
        id: prompt

        anchors.fill: parent

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: prompt
        }
    }
}
