// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_VERIFYREQUEST_P_H
#define LIBSAILFISHCRYPTO_VERIFYREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/verifyrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Crypto {

class VerifyRequestPrivate
{
    Q_DISABLE_COPY(VerifyRequestPrivate)

public:
    explicit VerifyRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    QByteArray m_signature;
    QByteArray m_data;
    Sailfish::Crypto::Key m_key;
    Sailfish::Crypto::CryptoManager::SignaturePadding m_padding;
    Sailfish::Crypto::CryptoManager::DigestFunction m_digestFunction;
    QString m_cryptoPluginName;
    Sailfish::Crypto::CryptoManager::VerificationStatus m_verificationStatus;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_VERIFYREQUEST_P_H
