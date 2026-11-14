// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_FINDSECRETSREQUEST_P_H
#define LIBSAILFISHSECRETS_FINDSECRETSREQUEST_P_H

#include "Secrets/secretsglobal.h"
#include "Secrets/secretmanager.h"
#include "Secrets/secret.h"

#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtCore/QVector>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Secrets {

class FindSecretsRequestPrivate
{
    Q_DISABLE_COPY(FindSecretsRequestPrivate)

public:
    explicit FindSecretsRequestPrivate();

    QPointer<Sailfish::Secrets::SecretManager> m_manager;
    QString m_collectionName;
    QString m_storagePluginName;
    Sailfish::Secrets::Secret::FilterData m_filter;
    Sailfish::Secrets::SecretManager::FilterOperator m_filterOperator;
    Sailfish::Secrets::SecretManager::UserInteractionMode m_userInteractionMode;
    QVector<Sailfish::Secrets::Secret::Identifier> m_identifiers;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Secrets::Request::Status m_status;
    Sailfish::Secrets::Result m_result;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_FINDSECRETSREQUEST_P_H
