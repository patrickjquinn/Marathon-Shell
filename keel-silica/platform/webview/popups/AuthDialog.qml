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

    property alias messageBundle: auth.messageBundle
    property alias hostname: auth.hostname
    property alias realm: auth.realm
    property alias passwordOnly: auth.passwordOnly
    property alias privateBrowsing: auth.privateBrowsing

    property alias usernameVisible: auth.usernameVisible
    property alias usernameAutofocus: auth.usernameAutofocus
    property alias usernamePrefillValue: auth.usernamePrefillValue
    property alias passwordPrefillValue: auth.passwordPrefillValue
    property alias rememberVisible: auth.rememberVisible
    property alias rememberPrefillValue: auth.rememberPrefillValue
    property alias rememberMessageBundle: auth.rememberMessageBundle

    property alias usernameValue: auth.usernameValue
    property alias passwordValue: auth.passwordValue
    property alias rememberValue: auth.rememberValue

    property alias acceptText: auth.acceptText
    property alias cancelText: auth.cancelText
    property alias title: auth.title
    property alias preventDialogsVisible: auth.preventDialogsVisible
    property alias preventDialogsPrefillValue: auth.preventDialogsPrefillValue
    property alias preventDialogsValue: auth.preventDialogsValue

    AuthPopupInterface {
        id: auth

        anchors.fill: parent

        usernameValue: username.text
        passwordValue: password.text
        rememberValue: remember.checked

        // This key isn't provided by gecko, so we define it explicitly
        //: Text on the Accept dialog button that accepts browser's auth request
        //% "Log In"
        acceptText: qsTrId("sailfish_components_webview_popups-la-accept_login")

        onAccepted: dialog.accept()
        onRejected: dialog.reject()

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: auth

            Column {
                width: parent.width

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    bottomPadding: Theme.paddingLarge
                    text: StringUtils.geckoKeyToString(auth.messageBundle)
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                }

                TextField {
                    id: username

                    width: parent.width
                    focus: auth.usernameVisible && auth.usernameAutofocus
                    visible: !auth.passwordOnly && auth.usernameVisible
                    //% "Enter your user name"
                    placeholderText: qsTrId("sailfish_components_webview_popups-la-enter_username")
                    //% "User name"
                    label: qsTrId("sailfish_components_webview_popups-la-user_name")

                    text: auth.usernamePrefillValue
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: password.focus = true
                }

                PasswordField {
                    id: password

                    width: parent.width
                    //% "Enter password"
                    placeholderText: qsTrId("sailfish_components_webview_popups-la-enter_password")
                    text: auth.passwordPrefillValue

                    EnterKey.iconSource: (username.text.length > 0 && text.length > 0)
                                         ? "image://theme/icon-m-enter-accept"
                                         : "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: auth.accepted()
                }

                TextSwitch {
                    id: remember

                    // If credentials are already remembered removing them via this is not feasible
                    // Better to hide the whole checkbox.
                    visible: auth.rememberVisible && !auth.privateBrowsing && !auth.rememberPrefillValue
                    checked: auth.rememberPrefillValue // bind the output value for when the prefill value is true.
                    text: StringUtils.geckoKeyToString(auth.rememberMessageBundle)
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    visible: auth.privateBrowsing
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor

                    //: Description label for user when private mode active (entered credentials are not saved)
                    //% "Credential storage is not available in private browsing mode"
                    text: qsTrId("sailfish_components_webview_popups-la-private_browsing_credentials_description")
                }
            }
        }
    }
}
