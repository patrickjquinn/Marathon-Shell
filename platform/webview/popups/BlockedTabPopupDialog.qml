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

    property alias host: blockedPopup.host
    property alias rememberValue: blockedPopup.rememberValue

    BlockedTabPopupInterface {
        id: blockedPopup

        anchors.fill: parent
        rememberValue: remember.checked

        Column {
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                //: Allow the page to open a popup window
                //% "Allow"
                acceptText: qsTrId("sailfish_components_webview_popups-he-load_popup")

                //: Deny the page from opening a popup window
                //% "Deny"
                cancelText: qsTrId("sailfish_components_webview_popups-he-block_popup")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - x * 2

                // We probably should truncate differently depending on screen size,
                // however, internally, Gecko truncates obnoxiously long uris to 150
                // for displaying in the UI.  So, do the same here.
                property string truncatedUri: blockedPopup.host.length > 150
                                            ? (blockedPopup.host.substring(0, 150) + "...")
                                            : blockedPopup.host

                //: %1 is the page that wants to load a popup
                //% "The page %1 attempted to open a new tab, which has been blocked. "
                //% "Would you like to allow it to open new tabs?"
                text: qsTrId("sailfish_components_webview_popups-la-popup_request").arg(truncatedUri)

                wrapMode: Text.WordWrap
                color: Theme.highlightColor
            }

            TextSwitch {
                id: remember

                //: Remember decision for this site for later use
                //% "Remember for this site"
                text: qsTrId("sailfish_components_webview_popups-remember_for_site")
                //% "You can change this setting in future by selecting the padlock icon in the toolbar, "
                //% "or from the Permissions page in Settings"
                description: qsTrId("sailfish_components_webview_popups-la-remember_popup_blocked_description")
            }
        }
    }
}
