// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_DECRYPTREQUEST_P_H
#define LIBSAILFISHCRYPTO_DECRYPTREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/decryptrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Crypto {

class DecryptRequestPrivate
{
    Q_DISABLE_COPY(DecryptRequestPrivate)

public:
    explicit DecryptRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    QByteArray m_data;
    QByteArray m_initializationVector;
    Sailfish::Crypto::Key m_key;
    Sailfish::Crypto::CryptoManager::BlockMode m_blockMode;
    Sailfish::Crypto::CryptoManager::EncryptionPadding m_padding;
    QByteArray m_authenticationData;
    QByteArray m_authenticationTag;
    QString m_cryptoPluginName;
    QByteArray m_plaintext;
    Sailfish::Crypto::CryptoManager::VerificationStatus m_verificationStatus;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_DECRYPTREQUEST_P_H
