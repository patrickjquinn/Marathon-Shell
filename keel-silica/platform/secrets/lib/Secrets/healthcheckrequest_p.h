// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Timur Kristóf <timur.kristof@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_HEALTHCHECKREQUEST_P_H
#define LIBSAILFISHSECRETS_HEALTHCHECKREQUEST_P_H

#include "Secrets/secretsglobal.h"
#include "Secrets/secretmanager.h"
#include "Secrets/secret.h"
#include "Secrets/healthcheckrequest.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Secrets {

class HealthCheckRequestPrivate
{
    Q_DISABLE_COPY(HealthCheckRequestPrivate)

public:
    explicit HealthCheckRequestPrivate();

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Secrets::Request::Status m_status;
    Sailfish::Secrets::Result m_result;

    QPointer<Sailfish::Secrets::SecretManager> m_manager;
    HealthCheckRequest::Health m_saltDataHealth;
    HealthCheckRequest::Health m_masterlockHealth;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_HEALTHCHECKREQUEST_P_H
