// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_ENCRYPTREQUEST_P_H
#define LIBSAILFISHCRYPTO_ENCRYPTREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/encryptrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Crypto {

class EncryptRequestPrivate
{
    Q_DISABLE_COPY(EncryptRequestPrivate)

public:
    explicit EncryptRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    QByteArray m_data;
    QByteArray m_initializationVector;
    Sailfish::Crypto::Key m_key;
    Sailfish::Crypto::CryptoManager::BlockMode m_blockMode;
    Sailfish::Crypto::CryptoManager::EncryptionPadding m_padding;
    QString m_cryptoPluginName;
    QByteArray m_ciphertext;
    QByteArray m_authenticationData;
    QByteArray m_authenticationTag;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_ENCRYPTREQUEST_P_H
