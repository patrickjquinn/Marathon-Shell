// SPDX-FileCopyrightText: 2016 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (C) 2016 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

pragma Singleton
import QtQml 2.2

// Modified by Shipwright for Keel: Sailfish's system settings plugin
// (org.nemomobile.systemsettings) is Qt 5 only, so Keel cannot read whether
// positioning is on. Qt WebEngine's geolocation needs Qt Positioning, which
// Keel's WebView does not use either: positioning reads as disabled.
QtObject {
    id: root

    property bool locationEnabled: false
}
