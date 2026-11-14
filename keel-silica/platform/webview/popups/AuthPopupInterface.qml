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

UserPromptInterface {
    // inputs
    property var messageBundle
    property string hostname
    property string realm
    property bool passwordOnly
    property bool privateBrowsing

    property bool usernameVisible
    property bool usernameAutofocus
    property string usernamePrefillValue
    property string passwordPrefillValue
    property bool rememberVisible // should only be shown if rememberVisible && !privateBrowsing
    property bool rememberPrefillValue
    property var rememberMessageBundle

    // outputs
    property string usernameValue
    property string passwordValue
    property bool rememberValue
}
