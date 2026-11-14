// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONRESPONSE_P_H
#define LIBSAILFISHSECRETS_INTERACTIONRESPONSE_P_H

#include "Secrets/result.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Secrets {

class InteractionResponsePrivate : public QSharedData {
public:
    InteractionResponsePrivate();
    InteractionResponsePrivate(const InteractionResponsePrivate &other);
    ~InteractionResponsePrivate();

    Sailfish::Secrets::Result m_result;
    QByteArray m_responseData;
};

} // Secrets

} // Sailfish

#endif // LIBSAILFISHSECRETS_INTERACTIONRESPONSE_P_H
