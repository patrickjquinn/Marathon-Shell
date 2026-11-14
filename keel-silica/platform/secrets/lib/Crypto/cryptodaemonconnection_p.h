// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_H
#define LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_H

// WARNING!
//
// This is private API, used for internal implementation only!
// No BC/SC guarantees are made for the methods in this file!

#include "Crypto/cryptoglobal.h"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QAtomicInt>
#include <QtCore/QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(lcSailfishCryptoDaemonConnection)

namespace Sailfish {

namespace Crypto {

class CryptoDaemonConnectionPrivate;
class SAILFISH_CRYPTO_API CryptoDaemonConnection : public QObject
{
    Q_OBJECT

public:
    virtual ~CryptoDaemonConnection();

    static CryptoDaemonConnection *instance();
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
    Q_DISABLE_COPY(CryptoDaemonConnection)
    CryptoDaemonConnection();
    CryptoDaemonConnectionPrivate *m_data;
    QAtomicInt m_refCount;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_H
