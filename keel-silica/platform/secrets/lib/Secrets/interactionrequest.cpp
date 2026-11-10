// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/interactionrequest.h"
#include "Secrets/interactionrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

InteractionRequestPrivate::InteractionRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype InteractionRequest
  \brief Allows a client request user input, mediated by the secrets service
  \inqmlmodule Sailfish.Secrets
  \inherits Request
*/

/*!
  \class InteractionRequest
  \brief Allows a client request user input, mediated by the secrets service
  \inmodule SailfishSecrets
  \inheaderfile Secrets/interactionrequest.h

  This class allows clients to request user input, via a system-mediated
  user interaction flow.  The user will be explicitly informed that the
  application has initiated the user interaction request, and that the
  supplied data should not be considered to be secure.

  Most applications should not have any need to use this request type,
  as they can usually show their own input dialog and ask the user for
  input directly that way, however some daemon services without any
  UI capability may need to use this request type to retrieve
  non-sensitive or transient data from the user.

  An example of retrieving user input follows:

  \code
  // Define the interaction request prompt parameters.
  Sailfish::Secrets::InteractionParameters uiParams;
  uiParams.setInputType(Sailfish::Secrets::InteractionParameters::AlphaNumericInput);
  uiParams.setEchoMode(Sailfish::Secrets::InteractionParameters::NormalEcho);
  uiParams.setPromptText(tr("Enter some data"));

  // Perform the request.
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::InteractionRequest ir;
  ir.setManager(&sm);
  ir.setInteractionParameters(&uiParams);
  ir.startRequest(); // status() will change to Finished when complete
  ir.waitForFinished(); // or better: connect to statusChanged()
  QByteArray userInput = ir.userInput();
  \endcode

  Note that if the user canceled the user input (or authentication
  or confirmation) dialog the result will contain the
  \c{Result::InteractionViewUserCanceledError} error code.
 */

/*!
  \brief Constructs a new InteractionRequest object with the given \a parent.
 */
InteractionRequest::InteractionRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new InteractionRequestPrivate)
{
}

/*!
  \brief Destroys the InteractionRequest
 */
InteractionRequest::~InteractionRequest()
{
}

/*!
  \qmlproperty InteractionParameters InteractionRequest::interactionParameters
  \brief The interaction parameters which allow customisation of the input prompt
*/

/*!
  \brief Returns the interaction parameters which allow customisation of the input prompt
 */
InteractionParameters InteractionRequest::interactionParameters() const
{
    Q_D(const InteractionRequest);
    return d->m_interactionParameters;
}

/*!
  \brief Sets the interaction parameters which allow customisation of the input prompt to \a uiParams
 */
void InteractionRequest::setInteractionParameters(const InteractionParameters &uiParams)
{
    Q_D(InteractionRequest);
    if (d->m_status != Request::Active && d->m_interactionParameters != uiParams) {
        d->m_interactionParameters = uiParams;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit interactionParametersChanged();
    }
}

/*!
  \brief Returns the user input which was retrieved for the client
 */
QByteArray InteractionRequest::userInput() const
{
    Q_D(const InteractionRequest);
    return d->m_userInput;
}

Request::Status InteractionRequest::status() const
{
    Q_D(const InteractionRequest);
    return d->m_status;
}

Result InteractionRequest::result() const
{
    Q_D(const InteractionRequest);
    return d->m_result;
}

SecretManager *InteractionRequest::manager() const
{
    Q_D(const InteractionRequest);
    return d->m_manager.data();
}

void InteractionRequest::setManager(SecretManager *manager)
{
    Q_D(InteractionRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void InteractionRequest::startRequest()
{
    Q_D(InteractionRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QByteArray> reply = d->m_manager->d_ptr->userInput(
                                                                d->m_interactionParameters);
        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::SecretManagerNotInitializedError,
                                 reply.error().message());
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Secrets::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            d->m_userInput = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit userInputChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QByteArray> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::InteractionViewError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_userInput = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->userInputChanged();
            });
        }
    }
}

void InteractionRequest::waitForFinished()
{
    Q_D(InteractionRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
