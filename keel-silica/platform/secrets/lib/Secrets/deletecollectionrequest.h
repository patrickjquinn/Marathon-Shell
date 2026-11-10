// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_DELETECOLLECTIONREQUEST_H
#define LIBSAILFISHSECRETS_DELETECOLLECTIONREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Secrets {

class DeleteCollectionRequestPrivate;
class SAILFISH_SECRETS_API DeleteCollectionRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName NOTIFY collectionNameChanged)
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName NOTIFY storagePluginNameChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode READ userInteractionMode WRITE setUserInteractionMode NOTIFY userInteractionModeChanged)

public:
    DeleteCollectionRequest(QObject *parent = Q_NULLPTR);
    ~DeleteCollectionRequest();

    QString collectionName() const;
    void setCollectionName(const QString &collectionName);

    QString storagePluginName() const;
    void setStoragePluginName(const QString &pluginName);

    Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode() const;
    void setUserInteractionMode(Sailfish::Secrets::SecretManager::UserInteractionMode mode);

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void collectionNameChanged();
    void storagePluginNameChanged();
    void userInteractionModeChanged();

private:
    QScopedPointer<DeleteCollectionRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(DeleteCollectionRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_DELETECOLLECTIONREQUEST_H
