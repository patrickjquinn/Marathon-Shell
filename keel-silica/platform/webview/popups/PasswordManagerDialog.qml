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

    property alias notificationType: passwordManager.notificationType
    property alias messageBundle: passwordManager.messageBundle
    property alias formData: passwordManager.formData
    property alias selectedIndex: passwordManager.selectedIndex
    property alias _internalData: passwordManager._internalData

    PasswordManagerPopupInterface {
        id: passwordManager

        anchors.fill: parent
        selectedIndex: selector.currentIndex

        Item {
            anchors.fill: parent

            DialogHeader {
                id: header

                //: Accept browser's request to save entered password
                //% "Save"
                acceptText: qsTrId("sailfish_components_webview_popups-he-accept_password_mgr_request")
                _glassOnly: true
            }

            Column {
                property bool _verticalCenter: passwordManager.notificationType !== "password-update-multiuser"

                anchors.horizontalCenter: parent.horizontalCenter
                y: _verticalCenter ? Math.round(parent.height - height) / 2.0 : header.height
                width: parent.width
                spacing: Theme.paddingMedium

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font {
                        family: Theme.fontFamilyHeading
                        pixelSize: Theme.fontSizeExtraLarge
                    }
                    color: Theme.highlightColor
                    opacity: Theme.opacityHigh

                    text: StringUtils.geckoKeyToString(passwordManager.messageBundle)
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.highlightColor
                    opacity: Theme.opacityHigh
                    //% "Logins and passwords can be managed from the Settings page"
                    text: qsTrId("sailfish_components_webview_popups-la-manage_paswords_hint")
                }

                ComboBox {
                    id: selector

                    visible: passwordManager.notificationType === "password-update-multiuser"
                    label: StringUtils.geckoKeyToString(passwordManager.formData["textBundle"] || "")
                    menu: ContextMenu {
                        Repeater {
                            model: passwordManager.formData["usernames"]
                            delegate: MenuItem {
                                text: model.modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
