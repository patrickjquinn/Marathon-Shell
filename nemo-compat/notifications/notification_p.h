// SPDX-FileCopyrightText: 2013 - 2019 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2013 - 2019 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#ifndef NOTIFICATION_P_H
#define NOTIFICATION_P_H

#include <notificationexport.h>

#include <QStringList>
#include <QDateTime>
#include <QVariantHash>
#include <QDBusArgument>
#include <QSharedPointer>

struct NotificationData
{
    struct ActionInfo {
        QString name;
        QString displayName;
    };

    QString appName;
    quint32 replacesId = 0;
    QString appIcon;
    QString summary;
    QString body;
    QList<ActionInfo> actions;
    QVariantHash hints;
    qint32 expireTimeout = -1;
    QString inputText;
};

class NotificationManagerProxy;

class NEMO_QML_PLUGIN_NOTIFICATIONS_EXPORT NotificationConnectionManager {
public:
    QSharedPointer<NotificationManagerProxy> proxy;
    QSharedPointer<QDBusConnection> dBusConnection;
    // For platforms where the Notifications interface is hosted on a p2p bus
    static bool useDBusConnection(const QDBusConnection &bus);
};

NEMO_QML_PLUGIN_NOTIFICATIONS_EXPORT QDBusArgument &operator<<(QDBusArgument &, const NotificationData &);
NEMO_QML_PLUGIN_NOTIFICATIONS_EXPORT const QDBusArgument &operator>>(const QDBusArgument &, NotificationData &);

Q_DECLARE_METATYPE(NotificationData)
Q_DECLARE_METATYPE(QList<NotificationData>)

#endif // NOTIFICATION_H
