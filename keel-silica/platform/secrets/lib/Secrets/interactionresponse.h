// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONRESPONSE_H
#define LIBSAILFISHSECRETS_INTERACTIONRESPONSE_H

#include "Secrets/secretsglobal.h"
#include "Secrets/result.h"

#include <QtCore/QByteArray>
#include <QtCore/QSharedDataPointer>
#include <QtCore/QMetaType>

namespace Sailfish {

namespace Secrets {

class InteractionResponsePrivate;
class SAILFISH_SECRETS_API InteractionResponse
{
    Q_GADGET
    Q_PROPERTY(Sailfish::Secrets::Result result READ result WRITE setResult)
    Q_PROPERTY(QByteArray responseData READ responseData WRITE setResponseData)

public:
    InteractionResponse();
    InteractionResponse(const InteractionResponse &other);
    ~InteractionResponse();
    InteractionResponse& operator=(const InteractionResponse &other);

    Sailfish::Secrets::Result result() const;
    void setResult(const Sailfish::Secrets::Result &result);

    QByteArray responseData() const;
    void setResponseData(const QByteArray &data);

private:
    QSharedDataPointer<InteractionResponsePrivate> d_ptr;
    friend class InteractionResponsePrivate;
};

bool operator==(const Sailfish::Secrets::InteractionResponse &lhs, const Sailfish::Secrets::InteractionResponse &rhs) SAILFISH_SECRETS_API;
bool operator!=(const Sailfish::Secrets::InteractionResponse &lhs, const Sailfish::Secrets::InteractionResponse &rhs) SAILFISH_SECRETS_API;
bool operator<(const Sailfish::Secrets::InteractionResponse &lhs, const Sailfish::Secrets::InteractionResponse &rhs) SAILFISH_SECRETS_API;

} // Secrets

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Secrets::InteractionResponse);
Q_DECLARE_TYPEINFO(Sailfish::Secrets::InteractionResponse, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHSECRETS_INTERACTIONRESPONSE_H

