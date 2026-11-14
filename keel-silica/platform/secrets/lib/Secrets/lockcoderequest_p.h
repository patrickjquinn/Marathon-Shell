// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_LOCKCODEREQUEST_P_H
#define LIBSAILFISHSECRETS_LOCKCODEREQUEST_P_H

#include "Secrets/secretsglobal.h"
#include "Secrets/lockcoderequest.h"
#include "Secrets/secretmanager.h"
#include "Secrets/interactionparameters.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Secrets {

class LockCodeRequestPrivate
{
    Q_DISABLE_COPY(LockCodeRequestPrivate)

public:
    explicit LockCodeRequestPrivate();

    QPointer<Sailfish::Secrets::SecretManager> m_manager;
    Sailfish::Secrets::LockCodeRequest::LockStatus m_lockStatus;
    Sailfish::Secrets::LockCodeRequest::LockCodeRequestType m_lockCodeRequestType;
    Sailfish::Secrets::LockCodeRequest::LockCodeTargetType m_lockCodeTargetType;
    Sailfish::Secrets::SecretManager::UserInteractionMode m_userInteractionMode;
    Sailfish::Secrets::InteractionParameters m_interactionParameters;
    QString m_lockCodeTarget;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Secrets::Request::Status m_status;
    Sailfish::Secrets::Result m_result;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_LOCKCODEREQUEST_P_H
