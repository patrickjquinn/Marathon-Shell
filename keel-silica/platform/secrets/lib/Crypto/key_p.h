// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_KEY_P_H
#define LIBSAILFISHCRYPTO_KEY_P_H

#include "Crypto/key.h"

#include <QtCore/QString>
#include <QtCore/QByteArray>
#include <QtCore/QVector>
#include <QtCore/QHash>
#include <QtCore/QDateTime>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class KeyIdentifierPrivate : public QSharedData
{
public:
    KeyIdentifierPrivate();
    KeyIdentifierPrivate(const KeyIdentifierPrivate &other);
    ~KeyIdentifierPrivate();

    QString m_name;
    QString m_collectionName;
    QString m_storagePluginName;
};

class KeyPrivate : public QSharedData
{
public:
    KeyPrivate();
    KeyPrivate(const KeyPrivate &other);
    ~KeyPrivate();

    Sailfish::Crypto::Key::FilterData m_filterData;
    QVector<QByteArray> m_customParameters;
    QByteArray m_publicKey;
    QByteArray m_privateKey;
    QByteArray m_secretKey;

    Sailfish::Crypto::Key::Identifier m_identifier;

    Sailfish::Crypto::Key::Origin m_origin;
    Sailfish::Crypto::CryptoManager::Algorithm m_algorithm;
    Sailfish::Crypto::CryptoManager::Operations m_operations;
    Sailfish::Crypto::Key::Components m_componentConstraints;
    int m_size;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_KEY_P_H
