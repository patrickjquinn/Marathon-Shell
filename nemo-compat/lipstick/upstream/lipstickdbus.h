// SPDX-FileCopyrightText: 2014 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only

// This file is part of lipstick, a QML desktop library
//
// Copyright (c) 2014 Jolla Ltd.
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.

#ifndef LIPSTICK_DBUS_H
#define LIPSTICK_DBUS_H

/* Global definitions for Lipstick's D-Bus service */

#define LIPSTICK_DBUS_SERVICE_NAME "org.nemomobile.lipstick"

#define LIPSTICK_DBUS_LAUNCHER_MODEL_PATH "/LauncherModel"
#define LIPSTICK_DBUS_LAUNCHER_MODEL_INTERFACE "org.nemomobile.lipstick.LauncherModel"
#define LIPSTICK_DBUS_LAUNCHER_MODEL_UPDATING_STARTED "updatingStarted"
#define LIPSTICK_DBUS_LAUNCHER_MODEL_UPDATING_PROGRESS "updatingProgress"
#define LIPSTICK_DBUS_LAUNCHER_MODEL_UPDATING_FINISHED "updatingFinished"
#define LIPSTICK_DBUS_LAUNCHER_MODEL_SHOW_UPDATING_PROGRESS "showUpdatingProgress"

#define LIPSTICK_DBUS_WINDOW_MODEL_PATH "/WindowModel"
#define LIPSTICK_DBUS_WINDOW_MODEL_INTERFACE "local.Lipstick.WindowModel"

#define LIPSTICK_DBUS_SCREENLOCK_PATH "/screenlock"
#define LIPSTICK_DBUS_SHUTDOWN_PATH "/shutdown"
#define LIPSTICK_DBUS_SCREENSHOT_PATH "/org/nemomobile/lipstick/screenshot"

#define LIPSTICK_DBUS_VPNAGENT_PATH "/org/nemomobile/lipstick/vpnagent"
#define CONNMAN_DBUS_VPN_SERVICE "net.connman.vpn"

#endif /* LIPSTICK_DBUS_H */
