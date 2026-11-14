// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_P_H
#define LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_P_H

#include "Crypto/cryptodaemonconnection_p.h"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>

#include <QtCore/QObject>
#include <QtCore/QPointer>

namespace Sailfish {

namespace Crypto {

class CryptoDaemonConnection;
class CryptoDaemonConnectionPrivate : public QObject
{
    Q_OBJECT

public:
    CryptoDaemonConnectionPrivate(CryptoDaemonConnection *parent = Q_NULLPTR);
    virtual ~CryptoDaemonConnectionPrivate() = default;
    QDBusConnection *connection() { return &m_connection; }
    bool connect();

public Q_SLOTS:
    void disconnected();

private:
    friend class CryptoDaemonConnection;
    QDBusConnection m_connection;
    QPointer<CryptoDaemonConnection> m_parent;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_CRYPTODAEMONCONNECTION_P_P_H
