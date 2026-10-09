// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_COLLECTIONNAMESREQUEST_H
#define LIBSAILFISHSECRETS_COLLECTIONNAMESREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QStringList>

namespace Sailfish {

namespace Secrets {

class CollectionNamesRequestPrivate;
class SAILFISH_SECRETS_API CollectionNamesRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName NOTIFY storagePluginNameChanged)
    Q_PROPERTY(QStringList collectionNames READ collectionNames NOTIFY collectionNamesChanged)

public:
    CollectionNamesRequest(QObject *parent = Q_NULLPTR);
    ~CollectionNamesRequest();

    QString storagePluginName() const;
    void setStoragePluginName(const QString &storagePluginName);

    QStringList collectionNames() const;

    Q_INVOKABLE bool isCollectionLocked(const QString &collectionName) const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void storagePluginNameChanged();
    void collectionNamesChanged();

private:
    QScopedPointer<CollectionNamesRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(CollectionNamesRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_COLLECTIONNAMESREQUEST_H
