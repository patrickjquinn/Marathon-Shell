// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_SEEDRANDOMDATAGENERATORREQUEST_P_H
#define LIBSAILFISHCRYPTO_SEEDRANDOMDATAGENERATORREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/generatekeyrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtCore/QByteArray>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Crypto {

class SeedRandomDataGeneratorRequestPrivate
{
    Q_DISABLE_COPY(SeedRandomDataGeneratorRequestPrivate)

public:
    explicit SeedRandomDataGeneratorRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    QString m_cryptoPluginName;
    QString m_csprngEngineName;
    double m_entropyEstimate;
    QByteArray m_seedData;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_SEEDRANDOMDATAGENERATORREQUEST_P_H
