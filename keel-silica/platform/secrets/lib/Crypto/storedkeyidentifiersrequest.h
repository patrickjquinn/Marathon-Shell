// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_STOREDKEYIDENTIFIERSREQUEST_H
#define LIBSAILFISHCRYPTO_STOREDKEYIDENTIFIERSREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/request.h"
#include "Crypto/key.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QVector>

namespace Sailfish {

namespace Crypto {

class CryptoManager;

class StoredKeyIdentifiersRequestPrivate;
class SAILFISH_CRYPTO_API StoredKeyIdentifiersRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName NOTIFY storagePluginNameChanged)
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName NOTIFY collectionNameChanged)
    Q_PROPERTY(QVector<Sailfish::Crypto::Key::Identifier> identifiers READ identifiers NOTIFY identifiersChanged)

public:
    StoredKeyIdentifiersRequest(QObject *parent = Q_NULLPTR);
    ~StoredKeyIdentifiersRequest();

    QString storagePluginName() const;
    void setStoragePluginName(const QString &pluginName);

    QString collectionName() const;
    void setCollectionName(const QString &name);

    QVector<Sailfish::Crypto::Key::Identifier> identifiers() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void storagePluginNameChanged();
    void collectionNameChanged();
    void identifiersChanged();

private:
    QScopedPointer<StoredKeyIdentifiersRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(StoredKeyIdentifiersRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_STOREDKEYIDENTIFIERSREQUEST_H
