// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_STORESECRETREQUEST_P_H
#define LIBSAILFISHSECRETS_STORESECRETREQUEST_P_H

#include "Secrets/secretsglobal.h"
#include "Secrets/storesecretrequest.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Secrets {

class StoreSecretRequestPrivate
{
    Q_DISABLE_COPY(StoreSecretRequestPrivate)

public:
    explicit StoreSecretRequestPrivate();

    QPointer<Sailfish::Secrets::SecretManager> m_manager;
    StoreSecretRequest::SecretStorageType m_secretStorageType;
    Sailfish::Secrets::Secret m_secret;
    QString m_encryptionPluginName;
    QString m_authenticationPluginName;
    Sailfish::Secrets::InteractionParameters m_interactionParameters;
    Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic m_deviceLockUnlockSemantic;
    Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic m_customLockUnlockSemantic;
    Sailfish::Secrets::SecretManager::AccessControlMode m_accessControlMode;
    Sailfish::Secrets::SecretManager::UserInteractionMode m_userInteractionMode;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Secrets::Request::Status m_status;
    Sailfish::Secrets::Result m_result;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_STORESECRETREQUEST_P_H
