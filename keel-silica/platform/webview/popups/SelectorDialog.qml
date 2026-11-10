// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
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

    canAccept: true

    property alias acceptText: prompt.acceptText
    property alias cancelText: prompt.cancelText
    property alias text: prompt.text
    property alias values: prompt.values
    property alias selectedIndex: prompt.selectedIndex

    property alias title: prompt.title

    SelectorPopupInterface {
        id: prompt

        anchors.fill: parent
        selectedIndex: selector.currentIndex

        onAccepted: dialog.accept()
        onRejected: dialog.reject()

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: prompt

            ComboBox {
                id: selector

                label: prompt.text
                menu: ContextMenu {
                    Repeater {
                        model: prompt.values
                        delegate: MenuItem {
                            text: model.modelData
                        }
                    }
                }
            }
        }
    }
}
