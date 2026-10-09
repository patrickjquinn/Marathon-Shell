// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CIPHERREQUEST_P_H
#define LIBSAILFISHCRYPTO_CIPHERREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/cipherrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QQueue>

#include <QtDBus/QDBusPendingCallWatcher>

namespace Sailfish {

namespace Crypto {

class CipherRequestPrivate
{
    Q_DISABLE_COPY(CipherRequestPrivate)

public:
    explicit CipherRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    CipherRequest::CipherMode m_cipherMode;
    CryptoManager::Operation m_operation;
    QByteArray m_data;
    QByteArray m_initializationVector;
    Sailfish::Crypto::Key m_key;
    Sailfish::Crypto::CryptoManager::BlockMode m_blockMode;
    Sailfish::Crypto::CryptoManager::EncryptionPadding m_encryptionPadding;
    Sailfish::Crypto::CryptoManager::SignaturePadding m_signaturePadding;
    Sailfish::Crypto::CryptoManager::DigestFunction m_digestFunction;
    QString m_cryptoPluginName;
    quint32 m_cipherSessionToken;
    QByteArray m_generatedData;
    Sailfish::Crypto::CryptoManager::VerificationStatus m_verificationStatus;

    QQueue<QDBusPendingCallWatcher*> m_watcherQueue;
    QHash<QDBusPendingCallWatcher*, bool> m_completedHash;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_CIPHERREQUEST_P_H
