// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_PLUGININFO_H
#define LIBSAILFISHCRYPTO_PLUGININFO_H

#include "Crypto/cryptoglobal.h"

#include <QtCore/QString>
#include <QtCore/QMetaType>
#include <QtCore/QSharedDataPointer>

namespace Sailfish {

namespace Crypto {

class PluginInfoPrivate;
class SAILFISH_CRYPTO_API PluginInfo
{
    Q_GADGET
    Q_PROPERTY(QString displayName READ displayName CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(int version READ version CONSTANT)
    Q_PROPERTY(StatusFlags statusFlags READ statusFlags CONSTANT)

public:
    enum Status {
        Unknown                     = 0,
        Available                   = 1 << 0,
        MasterUnlocked              = 1 << 1,
        PluginUnlocked              = 1 << 2,
        PluginSupportsLocking       = 1 << 3,
        PluginSupportsSetLockCode   = 1 << 4
    };
    Q_ENUM(Status)
    Q_DECLARE_FLAGS(StatusFlags, Status)
    Q_FLAG(StatusFlags)

    PluginInfo(const QString &displayName = QString(),
               const QString &name = QString(),
               int version = 0,
               StatusFlags status = PluginInfo::Unknown);
    PluginInfo(const PluginInfo &other);
    ~PluginInfo();

    PluginInfo &operator=(const Sailfish::Crypto::PluginInfo &other);

    QString displayName() const;

    QString name() const;

    int version() const;

    StatusFlags statusFlags() const;

private:
    QSharedDataPointer<PluginInfoPrivate> d_ptr;
    friend class PluginInfoPrivate;
};

bool operator==(const Sailfish::Crypto::PluginInfo &lhs, const Sailfish::Crypto::PluginInfo &rhs) SAILFISH_CRYPTO_API;
bool operator!=(const Sailfish::Crypto::PluginInfo &lhs, const Sailfish::Crypto::PluginInfo &rhs) SAILFISH_CRYPTO_API;
bool operator<(const Sailfish::Crypto::PluginInfo &lhs, const Sailfish::Crypto::PluginInfo &rhs) SAILFISH_CRYPTO_API;

} // Crypto

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Crypto::PluginInfo);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::PluginInfo, Q_MOVABLE_TYPE);

Q_DECLARE_METATYPE(Sailfish::Crypto::PluginInfo::Status);
Q_DECLARE_METATYPE(Sailfish::Crypto::PluginInfo::StatusFlags);
Q_DECLARE_OPERATORS_FOR_FLAGS(Sailfish::Crypto::PluginInfo::StatusFlags);

#endif // LIBSAILFISHCRYPTO_PLUGININFO_H
