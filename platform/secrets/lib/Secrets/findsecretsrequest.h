// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_FINDSECRETSREQUEST_H
#define LIBSAILFISHSECRETS_FINDSECRETSREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secret.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QVector>

namespace Sailfish {

namespace Secrets {

class FindSecretsRequestPrivate;
class SAILFISH_SECRETS_API FindSecretsRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName NOTIFY collectionNameChanged)
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName NOTIFY storagePluginNameChanged)
    Q_PROPERTY(Sailfish::Secrets::Secret::FilterData filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::FilterOperator filterOperator READ filterOperator WRITE setFilterOperator NOTIFY filterOperatorChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode READ userInteractionMode WRITE setUserInteractionMode NOTIFY userInteractionModeChanged)
    Q_PROPERTY(QVector<Sailfish::Secrets::Secret::Identifier> identifiers READ identifiers NOTIFY identifiersChanged)

public:
    FindSecretsRequest(QObject *parent = Q_NULLPTR);
    ~FindSecretsRequest();

    QString collectionName() const;
    void setCollectionName(const QString &name);

    QString storagePluginName() const;
    void setStoragePluginName(const QString &pluginName);

    Sailfish::Secrets::Secret::FilterData filter() const;
    void setFilter(const Sailfish::Secrets::Secret::FilterData &filter);

    Sailfish::Secrets::SecretManager::FilterOperator filterOperator() const;
    void setFilterOperator(Sailfish::Secrets::SecretManager::FilterOperator op);

    Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode() const;
    void setUserInteractionMode(Sailfish::Secrets::SecretManager::UserInteractionMode mode);

    QVector<Sailfish::Secrets::Secret::Identifier> identifiers() const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void collectionNameChanged();
    void storagePluginNameChanged();
    void filterChanged();
    void filterOperatorChanged();
    void userInteractionModeChanged();
    void identifiersChanged();

private:
    QScopedPointer<FindSecretsRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(FindSecretsRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_FINDSECRETSREQUEST_H
