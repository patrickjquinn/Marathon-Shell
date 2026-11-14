// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_KEYDERIVATIONPARAMETERS_P_H
#define LIBSAILFISHCRYPTO_KEYDERIVATIONPARAMETERS_P_H

#include "Crypto/cryptomanager.h"
#include "Crypto/key.h"

#include <QtCore/QByteArray>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class KeyDerivationParametersPrivate : public QSharedData
{
public:
    KeyDerivationParametersPrivate();
    KeyDerivationParametersPrivate(const KeyDerivationParametersPrivate &other);
    ~KeyDerivationParametersPrivate();

    QByteArray m_inputData;
    QByteArray m_salt;
    Sailfish::Crypto::CryptoManager::KeyDerivationFunction m_keyDerivationFunction;
    Sailfish::Crypto::CryptoManager::MessageAuthenticationCode m_keyDerivationMac;
    Sailfish::Crypto::CryptoManager::Algorithm m_keyDerivationAlgorithm;
    Sailfish::Crypto::CryptoManager::DigestFunction m_keyDerivationDigestFunction;
    qint64 m_memorySize;
    int m_iterations;
    int m_parallelism;
    int m_outputKeySize;
    QVariantMap m_customParameters;
};

} // Crypto

} // Sailfish

#endif // LIBSAILFISHCRYPTO_KEYDERIVATIONPARAMETERS_P_H
