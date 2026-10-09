// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_RESULT_P_H
#define LIBSAILFISHCRYPTO_RESULT_P_H

#include "Crypto/result.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class ResultPrivate : public QSharedData
{
public:
    ResultPrivate();
    ResultPrivate(const ResultPrivate &other);
    ~ResultPrivate();

    QString m_errorMessage;
    int m_storageErrorCode;
    Sailfish::Crypto::Result::ErrorCode m_errorCode;
    Sailfish::Crypto::Result::ResultCode m_code;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_RESULT_P_H
