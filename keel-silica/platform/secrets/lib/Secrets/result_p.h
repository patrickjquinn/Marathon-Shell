// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_RESULT_P_H
#define LIBSAILFISHSECRETS_RESULT_P_H

#include "Secrets/result.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Secrets {

class ResultPrivate : public QSharedData
{
public:
    ResultPrivate();
    ResultPrivate(const ResultPrivate &other);
    ~ResultPrivate();

    QString m_errorMessage;
    Sailfish::Secrets::Result::ErrorCode m_errorCode;
    Sailfish::Secrets::Result::ResultCode m_code;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_RESULT_P_H
