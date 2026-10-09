// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Timur Kristóf <timur.kristof@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_HEATHCHECKREQUEST_H
#define LIBSAILFISHSECRETS_HEATHCHECKREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secret.h"
#include "Secrets/secretmanager.h"
#include "Secrets/plugininfo.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QVector>

namespace Sailfish {

namespace Secrets {

class HealthCheckRequestPrivate;
class SAILFISH_SECRETS_API HealthCheckRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(Health saltDataHealth READ saltDataHealth NOTIFY saltDataHealthChanged)
    Q_PROPERTY(Health masterlockHealth READ masterlockHealth NOTIFY masterlockHealthChanged)
    Q_PROPERTY(bool isHealthy READ isHealthy NOTIFY isHealthyChanged)

public:
    enum Health {
        HealthOK = 0,
        HealthUnknown,
        HealthCorrupted,
        HealthOtherError,
    };
    Q_ENUM(Health)

    HealthCheckRequest(QObject *parent = Q_NULLPTR);
    ~HealthCheckRequest() Q_DECL_OVERRIDE;

    Health saltDataHealth() const;
    Health masterlockHealth() const;
    bool isHealthy() const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void saltDataHealthChanged();
    void masterlockHealthChanged();
    void isHealthyChanged();

private:
    QScopedPointer<HealthCheckRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(HealthCheckRequest)
};

} // namespace Secrets

} // namespace Sailfish

Q_DECLARE_METATYPE(::Sailfish::Secrets::HealthCheckRequest::Health);

#endif // LIBSAILFISHSECRETS_HEATHCHECKREQUEST_H
