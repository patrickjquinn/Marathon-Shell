// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2014-2019 Jolla Ltd
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (C) 2014-2019 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
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
#ifndef COMMONDEFS_H
#define COMMONDEFS_H

#include <QString>
// Define string constants for different XML elements.

namespace Buteo {

const QString ATTR_NAME("name");
const QString ATTR_TYPE("type");
const QString ATTR_VALUE("value");
const QString ATTR_DEFAULT("default");
const QString ATTR_LABEL("label");
const QString ATTR_VISIBLE("visible");
const QString ATTR_READONLY("readonly");
const QString ATTR_ADDED("added");
const QString ATTR_DELETED("deleted");
const QString ATTR_MODIFIED("modified");
const QString ATTR_UID("uid");
const QString ATTR_STATUS("status");
const QString ATTR_TIME("time");
const QString ATTR_INTERVAL("interval");
const QString ATTR_BEGIN("begin");
const QString ATTR_END("end");
const QString ATTR_DAYS("days");
const QString ATTR_MAJOR_CODE("majorcode");
const QString ATTR_MINOR_CODE("minorcode");
const QString ATTR_ENABLED("enabled");
const QString ATTR_SYNC_CONFIGURE("syncconfiguredtime");
const QString ATTR_EXTERNAL_SYNC("externalsync");

const QString TAG_FIELD("field");
const QString TAG_PROFILE("profile");
const QString TAG_KEY("key");
const QString TAG_OPTION("option");
const QString TAG_TARGET_RESULTS("target");
const QString TAG_SYNC_RESULTS("syncresults");
const QString TAG_SYNC_LOG("synclog");
const QString TAG_LOCAL("local");
const QString TAG_REMOTE("remote");
const QString TAG_ADDED_ITEM("addedItem");
const QString TAG_DELETED_ITEM("deletedItem");
const QString TAG_MODIFIED_ITEM("modifiedItem");
const QString TAG_SCHEDULE("schedule");
const QString TAG_RUSH("rush");
const QString TAG_ERROR_ATTEMPTS("attempts");
const QString TAG_ATTEMPT_DELAY("attemptdelay");

const QString KEY_ENABLED("enabled");
const QString KEY_DISPLAY_NAME("displayname");
const QString KEY_ACTIVE("active");
const QString KEY_USE_ACCOUNTS("use_accounts");
const QString KEY_SYNC_SCHEDULED("scheduled");
const QString KEY_PLUGIN("plugin");
const QString KEY_BACKEND("backend");
const QString KEY_ACCOUNT_ID("accountid");
const QString KEY_USERNAME("Username");
const QString KEY_PASSWORD("Password");
const QString KEY_HIDDEN("hidden");
const QString KEY_PROTECTED("protected");
const QString KEY_DESTINATION_TYPE("destinationtype");
const QString KEY_SYNC_DIRECTION("Sync Direction");
const QString KEY_FORCE_SLOW_SYNC("force_slow_sync");
const QString KEY_CONFLICT_RESOLUTION_POLICY("conflictpolicy");
const QString KEY_BT_ADDRESS("bt_address");
const QString KEY_REMOTE_ID("remote_id");
const QString KEY_REMOTE_DATABASE("Remote database");
const QString KEY_BT_NAME("bt_name");
const QString KEY_BT_TRANSPORT("bt_transport");
const QString KEY_USB_TRANSPORT("usb_transport");
const QString KEY_INTERNET_TRANSPORT("internet_transport");
const QString KEY_LOAD_WITHOUT_TRANSPORT("load_without_transport");
const QString KEY_CAPS_MODIFIED("caps_modified");
const QString KEY_SYNC_SINCE_DAYS_PAST("sync_since_days_past"); // sync from this many days before the current date
const QString KEY_SYNC_ALWAYS_UP_TO_DATE("sync_always_up_to_date");
const QString KEY_SYNC_EXTERNALLY("sync_externally");
const QString KEY_SOC("sync_on_change");
const QString KEY_SOC_AFTER("sync_on_change_after");
const QString KEY_LOCAL_URI("Local URI");
const QString KEY_ALWAYS_ON_ENABLED("always_on_enabled");
const QString KEY_REMOTE_NAME("remote_name");
const QString KEY_UUID("uuid");
const QString KEY_NOTES_UUID("notes_uuid");
const QString KEY_STORAGE_UPDATED("storage_updated");
const QString KEY_HTTP_PROXY_HOST("http_proxy_host");
const QString KEY_HTTP_PROXY_PORT("http_proxy_port");
const QString KEY_PROFILE_ID("profile_id");
const QString KEY_INTERNET_CONNECTION_TYPES("internet_connection_types");

const QString BOOLEAN_TRUE("true");
const QString BOOLEAN_FALSE("false");

const QString VALUE_ONLINE("online");
const QString VALUE_DEVICE("device");
const QString VALUE_TWO_WAY("two-way");
const QString VALUE_FROM_REMOTE("from-remote");
const QString VALUE_TO_REMOTE("to-remote");
const QString VALUE_PREFER_REMOTE("prefer remote");
const QString VALUE_PREFER_LOCAL("prefer local");

// Indent size for profile XML output.
const int PROFILE_INDENT = 4;

const QString PC_SYNC("PC-SYNC");
}

#endif // COMMONDEFS_H
