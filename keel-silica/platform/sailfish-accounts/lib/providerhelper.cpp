// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "providerhelper.h"

// AccessControl
#include <sailfishaccesscontrol.h>
#include <unistd.h>

const static auto USER_GROUP_HEADER = QStringLiteral("user-group:");

bool allowedProvider(const QSet<QString> &tags)
{
    for (const QString &tag : tags) {
        if (tag.startsWith(USER_GROUP_HEADER)) {
            // Hide provider if calling user is not in the required group
            if (!sailfish_access_control_hasgroup(getuid(), tag.mid(USER_GROUP_HEADER.length()).toUtf8())) {
                return false;
            }
        }
    }

    return true;
}
