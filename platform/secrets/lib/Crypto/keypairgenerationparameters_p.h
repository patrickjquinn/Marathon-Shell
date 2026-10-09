// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_P_H
#define LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_P_H

#include "Crypto/keypairgenerationparameters.h"

#include <QtCore/QByteArray>
#include <QtCore/QVariantMap>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class KeyPairGenerationParametersPrivate : public QSharedData
{
public:
    KeyPairGenerationParametersPrivate();
    KeyPairGenerationParametersPrivate(const KeyPairGenerationParametersPrivate &other);
    ~KeyPairGenerationParametersPrivate();

    KeyPairGenerationParameters::KeyPairType m_keyPairType;
    QVariantMap m_customParameters;
    QVariantMap m_subclassParameters;

    // for use in serialization
    static QVariantMap subclassParameters(const KeyPairGenerationParameters &kpgParams);
    static void setSubclassParameters(KeyPairGenerationParameters &kpgParams, const QVariantMap &params);
};

} // Crypto

} // Sailfish

#endif // LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_P_H
