// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONREQUEST_H
#define LIBSAILFISHSECRETS_INTERACTIONREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/result.h"
#include "Secrets/secretmanager.h"
#include "Secrets/interactionparameters.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QByteArray>

namespace Sailfish {

namespace Secrets {

class InteractionRequestPrivate;
class SAILFISH_SECRETS_API InteractionRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(Sailfish::Secrets::InteractionParameters interactionParameters READ interactionParameters WRITE setInteractionParameters NOTIFY interactionParametersChanged)

public:
    InteractionRequest(QObject *parent = Q_NULLPTR);
    ~InteractionRequest();

    Sailfish::Secrets::InteractionParameters interactionParameters() const;
    void setInteractionParameters(const Sailfish::Secrets::InteractionParameters &uiParams);

    QByteArray userInput() const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void interactionParametersChanged();
    void userInputChanged();

private:
    QScopedPointer<InteractionRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(InteractionRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_INTERACTIONREQUEST_H
