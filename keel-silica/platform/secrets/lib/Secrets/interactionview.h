// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONVIEW_H
#define LIBSAILFISHSECRETS_INTERACTIONVIEW_H

#include "Secrets/secretsglobal.h"
#include "Secrets/result.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/interactionresponse.h"

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtCore/QList>
#include <QtCore/QString>
#include <QtCore/QSharedDataPointer>

namespace Sailfish {

namespace Secrets {

/*
 *  The InteractionView interface provides API to trigger or cancel
 *  different types of user interaction.  It is invoked by the
 *  InteractionService in response to communication from the sailfishsecretsd
 *  process, and it in turn invokes the sendResponse() method
 *  of the InteractionService when user interaction is complete.
 */
class SecretManager;
class InteractionService;
class InteractionViewPrivate;
class SAILFISH_SECRETS_API InteractionView
{
public:
    InteractionView();
    InteractionView(const InteractionView &other);
    virtual ~InteractionView();

protected:
    void sendResponse(const Sailfish::Secrets::InteractionResponse &response);

    virtual void performRequest(const Sailfish::Secrets::InteractionParameters &request) = 0;
    virtual void continueRequest(const Sailfish::Secrets::InteractionParameters &request) = 0;
    virtual void cancelRequest() = 0;
    virtual void finishRequest() = 0;

protected:
    void registerWithSecretManager(SecretManager *manager);
    SecretManager *registeredWithSecretManager() const;

private:
    friend class InteractionService;
    bool performRequest(QObject *sender, const Sailfish::Secrets::InteractionParameters &request);
    bool continueRequest(QObject *sender, const Sailfish::Secrets::InteractionParameters &request);
    bool cancelRequest(QObject *sender);
    bool finishRequest(QObject *sender);
    QSharedDataPointer<InteractionViewPrivate> d_ptr;
    friend class InteractionViewPrivate;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_INTERACTIONVIEW_H
