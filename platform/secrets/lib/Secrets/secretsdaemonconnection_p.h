// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRETSDAEMONCONNECTION_H
#define LIBSAILFISHSECRETS_SECRETSDAEMONCONNECTION_H

#include "Secrets/secretsglobal.h"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QAtomicInt>
#include <QtCore/QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(lcSailfishSecretsDaemonConnection)

namespace Sailfish {

namespace Secrets {

class SecretsDaemonConnectionPrivate;
class SAILFISH_SECRETS_API SecretsDaemonConnection : public QObject
{
    Q_OBJECT

public:
    virtual ~SecretsDaemonConnection();

    static SecretsDaemonConnection *instance();
    static void releaseInstance();

    bool connect();
    QDBusConnection *connection();
    QDBusInterface *createInterface(const QString &objectPath,
                                    const QString &interface,
                                    QObject *parent = Q_NULLPTR);

    static void registerDBusTypes();

Q_SIGNALS:
    void disconnected();

private:
    Q_DISABLE_COPY(SecretsDaemonConnection)
    SecretsDaemonConnection();
    SecretsDaemonConnectionPrivate *m_data;
    QAtomicInt m_refCount;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_SECRETSDAEMONCONNECTION_H
