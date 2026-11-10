// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 *
 * Contact: Sateesh Kavuri <sateesh.kavuri@nokia.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 *
 */

#ifndef SYNCCOMMONDEFS_H
#define SYNCCOMMONDEFS_H

#include <QMetaType>
#include <QDir>
#include <QStandardPaths>
// Modified by Shipwright for Qt 6: QNetworkConfiguration is gone; the
// values below are Qt 5's QNetworkConfiguration::BearerType numbers, which
// sync profiles written by Qt 5 msyncd contain.

namespace Sync {

const QString syncConfigDir();
const QString syncCacheDir(); // deprecated

enum SyncStatus {
    SYNC_QUEUED = 0,
    SYNC_STARTED,
    SYNC_PROGRESS,
    SYNC_ERROR,
    SYNC_DONE,
    SYNC_ABORTED,
    SYNC_CANCELLED,
    SYNC_STOPPING,
    SYNC_NOTPOSSIBLE,
    SYNC_AUTHENTICATION_FAILURE,
    SYNC_DATABASE_FAILURE,
    SYNC_CONNECTION_ERROR,
    SYNC_SERVER_FAILURE,
    SYNC_BAD_REQUEST,
    SYNC_PLUGIN_ERROR,
    SYNC_PLUGIN_TIMEOUT
};

// UI needs to display a detailed Progress for the Current ongoing sync
enum SyncProgressDetail {
    SYNC_PROGRESS_INITIALISING = 201,
    SYNC_PROGRESS_SENDING_ITEMS,
    SYNC_PROGRESS_RECEIVING_ITEMS,
    SYNC_PROGRESS_FINALISING
};

enum TransferDatabase {
    LOCAL_DATABASE = 0,
    REMOTE_DATABASE
};

enum TransferType {
    ITEM_ADDED = 0,
    ITEM_MODIFIED,
    ITEM_DELETED,
    ITEM_ERROR
};

enum ConnectivityType {
    CONNECTIVITY_USB,
    CONNECTIVITY_BT,
    CONNECTIVITY_INTERNET
};

enum InternetConnectionType {
    INTERNET_CONNECTION_UNKNOWN = 0 /* BearerUnknown */,
    INTERNET_CONNECTION_ETHERNET = 1 /* BearerEthernet */,
    INTERNET_CONNECTION_WLAN = 2 /* BearerWLAN */,
    INTERNET_CONNECTION_2G = 3 /* Bearer2G */,
    INTERNET_CONNECTION_3G = 11 /* Bearer3G */,
    INTERNET_CONNECTION_4G = 12 /* Bearer4G */,
    INTERNET_CONNECTION_CDMA2000 = 4 /* BearerCDMA2000 */,
    INTERNET_CONNECTION_WCDMA = 5 /* BearerWCDMA */,
    INTERNET_CONNECTION_HSPA = 6 /* BearerHSPA */,
    INTERNET_CONNECTION_BLUETOOTH = 7 /* BearerBluetooth */,
    INTERNET_CONNECTION_WIMAX = 8 /* BearerWiMAX */,
    INTERNET_CONNECTION_EVDO = 9 /* BearerEVDO */,
    INTERNET_CONNECTION_LTE = 10 /* BearerLTE */
};

// These are values that can be used for the SyncSchedule::interval, to specify sync intervals
// that should be specially handled (instead of treating them as minute intervals). This allows
// special intervals to be handled without additional SyncSchedule attributes.
enum ExtendedSyncInterval : unsigned int {
    // Sync is scheduled one month after the last successful sync.
    // Start the named interval values at an unlikely minute-based interval
    // ((365 * 24 * 60 * 2) = 1051200 minutes = 2 years)
    SYNC_INTERVAL_MONTHLY = 365 * 24 * 60 * 2,
    // Sync is scheduled on the first day of each month.
    SYNC_INTERVAL_FIRST_DAY_OF_MONTH,

    // Sync is scheduled on the last day of each month.
    SYNC_INTERVAL_LAST_DAY_OF_MONTH
};

} // namespace Sync

Q_DECLARE_METATYPE(Sync::SyncStatus);
Q_DECLARE_METATYPE(Sync::TransferDatabase);
Q_DECLARE_METATYPE(Sync::TransferType);
Q_DECLARE_METATYPE(Sync::ConnectivityType);

#endif // SYNCCOMMONDEFS_H
