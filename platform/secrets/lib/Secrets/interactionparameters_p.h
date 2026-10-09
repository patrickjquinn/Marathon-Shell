// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONPARAMETERS_P_H
#define LIBSAILFISHSECRETS_INTERACTIONPARAMETERS_P_H

#include "Secrets/interactionparameters.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Secrets {

class InteractionParametersPrivate : public QSharedData {
public:
    InteractionParametersPrivate();
    InteractionParametersPrivate(const InteractionParametersPrivate &other);
    ~InteractionParametersPrivate();

    QString m_secretName;
    QString m_collectionName;
    QString m_pluginName;
    QString m_applicationId;
    Sailfish::Secrets::InteractionParameters::Operation m_operation = Sailfish::Secrets::InteractionParameters::UnknownOperation;
    QString m_authenticationPluginName;
    Sailfish::Secrets::InteractionParameters::PromptText m_promptText;
    Sailfish::Secrets::InteractionParameters::InputType m_inputType = Sailfish::Secrets::InteractionParameters::UnknownInput;
    Sailfish::Secrets::InteractionParameters::EchoMode m_echoMode = Sailfish::Secrets::InteractionParameters::PasswordEcho;
};

} // Secrets

} // Sailfish

#endif // LIBSAILFISHSECRETS_INTERACTIONPARAMETERS_P_H
