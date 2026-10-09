// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRET_P_H
#define LIBSAILFISHSECRETS_SECRET_P_H

#include "Secrets/secret.h"

#include <QtCore/QString>
#include <QtCore/QByteArray>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Secrets {

class SecretIdentifierPrivate : public QSharedData
{
public:
    SecretIdentifierPrivate();
    SecretIdentifierPrivate(const SecretIdentifierPrivate &other);
    ~SecretIdentifierPrivate();

    QString m_name;
    QString m_collectionName;
    QString m_storagePluginName;
};

class SecretPrivate : public QSharedData
{
public:
    SecretPrivate();
    SecretPrivate(const SecretPrivate &other);
    ~SecretPrivate();

    Sailfish::Secrets::Secret::FilterData m_filterData;
    Sailfish::Secrets::Secret::Identifier m_identifier;
    QByteArray m_data;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_SECRET_P_H
