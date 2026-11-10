// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_INTERACTIONREQUEST_P_H
#define LIBSAILFISHCRYPTO_INTERACTIONREQUEST_P_H

#include "Crypto/interactionparameters.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class InteractionParametersPrivate : public QSharedData {
public:
    InteractionParametersPrivate();
    InteractionParametersPrivate(const InteractionParametersPrivate &other);
    ~InteractionParametersPrivate();

    QString m_keyName;
    QString m_collectionName;
    QString m_pluginName;
    QString m_applicationId;
    Sailfish::Crypto::InteractionParameters::Operation m_operation = Sailfish::Crypto::InteractionParameters::UnknownOperation;
    QString m_authenticationPluginName;
    Sailfish::Crypto::InteractionParameters::PromptText m_promptText;
    Sailfish::Crypto::InteractionParameters::InputType m_inputType = Sailfish::Crypto::InteractionParameters::UnknownInput;
    Sailfish::Crypto::InteractionParameters::EchoMode m_echoMode = Sailfish::Crypto::InteractionParameters::PasswordEcho;
};

} // Crypto

} // Sailfish

#endif // LIBSAILFISHCRYPTO_INTERACTIONREQUEST_P_H
