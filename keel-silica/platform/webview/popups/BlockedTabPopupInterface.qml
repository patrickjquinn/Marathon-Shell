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

Item {
    // Popup shown when a site tab popup is blocked.
    // User should be given the option to allow the site popup to be shown
    // (i.e. accepted() signal) or disallow the site popup to be shown
    // (i.e. rejected() signal), and to either remember the decision
    // for this site, or not.

    // inputs
    property string host

    // outputs
    property bool rememberValue
    signal accepted
    signal rejected
}
