// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_GETSECRETREQUEST_H
#define LIBSAILFISHSECRETS_GETSECRETREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secret.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Secrets {

class StoredSecretRequestPrivate;
class SAILFISH_SECRETS_API StoredSecretRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(Sailfish::Secrets::Secret::Identifier identifier READ identifier WRITE setIdentifier NOTIFY identifierChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode READ userInteractionMode WRITE setUserInteractionMode NOTIFY userInteractionModeChanged)
    Q_PROPERTY(Sailfish::Secrets::Secret secret READ secret NOTIFY secretChanged)

public:
    StoredSecretRequest(QObject *parent = Q_NULLPTR);
    ~StoredSecretRequest();

    Sailfish::Secrets::Secret::Identifier identifier() const;
    void setIdentifier(const Sailfish::Secrets::Secret::Identifier &ident);

    Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode() const;
    void setUserInteractionMode(Sailfish::Secrets::SecretManager::UserInteractionMode mode);

    Sailfish::Secrets::Secret secret() const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void identifierChanged();
    void userInteractionModeChanged();
    void secretChanged();

private:
    QScopedPointer<StoredSecretRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(StoredSecretRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_GETSECRETREQUEST_H
