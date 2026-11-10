// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "interactionservice_p.h"
#include "secretmanager.h"
#include "secretmanager_p.h"
#include "interactionview.h"
#include "interactionparameters.h"
#include "interactionresponse.h"

#include <QtCore/QDir>
#include <QtCore/QUuid>
#include <QtCore/QPointer>
#include <QtCore/QSharedData>
#include <QtCore/QStandardPaths>
#include <QtCore/QLoggingCategory>

// for getpid()
#include <sys/types.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcSailfishSecretsUi, "org.sailfishos.secrets.interaction", QtWarningMsg)

using namespace Sailfish::Secrets;

void SecretManagerPrivate::handleUiConnection(const QDBusConnection &connection)
{
    qCDebug(lcSailfishSecretsUi) << "InteractionService received new client p2p connection:" << connection.name();
    QDBusConnection clientConnection(connection);
    if (!clientConnection.registerObject(QLatin1String("/"),
#if QT_VERSION >= QT_VERSION_CHECK(5, 5, 0)
                                         QLatin1String("org.sailfishos.secrets.interaction"),
#endif
                                         m_uiService,
                                         QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qCWarning(lcSailfishSecretsUi) << "Could not register object for ui connection!";
    } else {
        qCDebug(lcSailfishSecretsUi) << "Registered ui object with the client connection!";
    }
}

InteractionService::InteractionService(SecretManagerPrivate *parent)
    : QObject(parent)
    , m_parent(parent)
    , m_dbusServer(Q_NULLPTR)
    , m_activeConnection(QLatin1String("org.sailfishos.secrets.interaction.invalidConnection"))
    , m_activeRequestState(Inactive)
    , m_connectedClients(0)
{
}

bool InteractionService::registerServer()
{
    if (!m_address.isEmpty()) {
        // already registered.
        return true;
    }

    const QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (path.isEmpty()) {
        qCWarning(lcSailfishSecretsUi) << "No writable runtime directory found, cannot create socket file";
        return false;
    }

    QDir dir(path);
    if (!dir.mkpath(dir.absolutePath())) {
        qCWarning(lcSailfishSecretsUi) << "Could not create socket file directory";
        return false;
    }

    const QString file = QString::fromUtf8("%1/%2-%3").arg(dir.absolutePath(), QLatin1String("sailfishsecretsd-uiSocket"), QString::number(getpid()));
    const QString address = QString::fromUtf8("unix:path=%1").arg(file);

    m_dbusServer = new QDBusServer(address, this);
    connect(m_dbusServer, &QDBusServer::newConnection,
            m_parent, &SecretManagerPrivate::handleUiConnection);

    m_address = address;
    qCDebug(lcSailfishSecretsUi) << "InteractionService listening for ui p2p connections on address:" << m_address;
    return true;
}

void InteractionService::sendResponse(
        const InteractionResponse &response)
{
    if (m_activeRequestId.isEmpty()) {
        qCDebug(lcSailfishSecretsUi) << "Refusing to send response for canceled or finished request";
        return;
    }

    // transition to waiting state, we need sailfishsecretsd to tell us whether we're finished or not.
    m_activeRequestState = InteractionService::Waiting;

    // send the response.
    m_activeReply << QVariant::fromValue<InteractionResponse>(response);
    m_activeReply << QVariant::fromValue<QString>(m_activeRequestId);
    m_activeConnection.send(m_activeReply);
}

void InteractionService::performInteractionRequest(
        const InteractionParameters &request,
        const QDBusMessage &message,
        InteractionResponse &response,
        QString &requestId)
{
    Q_UNUSED(requestId) // outparam, will be set in sendResponse().
    qCDebug(lcSailfishSecretsUi) << "InteractionService received performInteractionRequest...";
    if (!m_activeRequestId.isEmpty()) {
        response.setResult(Result(Result::InteractionServiceRequestBusyError,
                                  QLatin1String("Ui service is busy handling another request")));
    } else if (!m_parent->m_interactionView || !m_parent->m_interactionView->performRequest(this, request)) {
        response.setResult(Result(Result::InteractionViewUnavailableError,
                                  QLatin1String("Cannot perform ui request: view busy or no view registered")));
    } else {
        // successfully triggered the request in the view.
        if (m_activeConnection.isConnected()) {
            m_activeConnection.disconnect(QString(), // any service
                                          QLatin1String("/org/freedesktop/DBus/Local"),
                                          QLatin1String("org.freedesktop.DBus.Local"),
                                          QLatin1String("Disconnected"),
                                          this, SLOT(clientDisconnected()));
        }
        m_activeRequestId = QUuid::createUuid().toString();
        m_activeConnection = connection();
        m_activeConnection.connect(QString(), // any service
                                   QLatin1String("/org/freedesktop/DBus/Local"),
                                   QLatin1String("org.freedesktop.DBus.Local"),
                                   QLatin1String("Disconnected"),
                                   this, SLOT(clientDisconnected()));
        m_activeReply = message.createReply();
        message.setDelayedReply(true);
    }
}

// The sailfishsecretsd process is telling us that more user-interaction is
// required before the request is complete.
void InteractionService::continueInteractionRequest(
        const QString &requestId,
        const InteractionParameters &request,
        const QDBusMessage &message,
        InteractionResponse &response)
{
    qCDebug(lcSailfishSecretsUi) << "InteractionService received continueInteractionRequest...";
    if (requestId != m_activeRequestId) {
        response.setResult(Result(Result::InteractionServiceRequestInvalidError,
                                  QString::fromLatin1("Cannot continue non-active ui request: %1").arg(requestId)));
    } else if (m_activeRequestState != InteractionService::Waiting) {
        response.setResult(Result(Result::InteractionServiceRequestBusyError,
                                  QString::fromLatin1("Cannot continue non-waiting ui request: %1").arg(requestId)));
    } else if (!m_parent->m_interactionView || !m_parent->m_interactionView->continueRequest(this, request)) {
        response.setResult(Result(Result::InteractionViewUnavailableError,
                                  QLatin1String("Cannot continue ui request: view busy or no view registered")));
    } else {
        // successfully triggered the sign on request in the view.
        m_activeConnection = connection();
        m_activeReply = message.createReply();
        message.setDelayedReply(true);
    }
}

// The sailfishsecretsd process is telling us to cancel the request.
void InteractionService::cancelInteractionRequest(
        const QString &requestId,
        const QDBusMessage &message,
        Result &result)
{
    Q_UNUSED(message);
    qCDebug(lcSailfishSecretsUi) << "InteractionService received cancelInteractionRequest...";
    if (requestId != m_activeRequestId) {
        result = Result(Result::InteractionServiceRequestInvalidError,
                        QString::fromLatin1("Cannot cancel non-active ui request: %1").arg(requestId));
    } else if (!m_parent->m_interactionView || !m_parent->m_interactionView->cancelRequest(this)) {
        result = Result(Result::InteractionViewUnavailableError,
                        QLatin1String("Cannot cancel ui request: view busy or no view registered"));
    } else {
        // don't destroy the connection yet (wait for client disconnection first)
        // but set the connection state to inactive, so that we can accept new clients.
        m_activeRequestState = InteractionService::Inactive;
        m_activeRequestId = QString();
        result = Result(Result::Succeeded);
    }
}

// The sailfishsecretsd process is telling us that it has finished
// handling the response, and no further user interaction is required.
void InteractionService::finishInteractionRequest(
        const QString &requestId,
        const QDBusMessage &message,
        Result &result)
{
    Q_UNUSED(message);
    qCDebug(lcSailfishSecretsUi) << "InteractionService received finishInteractionRequest...";
    if (requestId != m_activeRequestId) {
        result = Result(Result::InteractionServiceRequestInvalidError,
                        QString::fromLatin1("Cannot finish non-active ui request: %1").arg(requestId));
    } else if (m_activeRequestState != InteractionService::Waiting) {
        result = Result(Result::InteractionServiceRequestBusyError,
                        QString::fromLatin1("Cannot finish non-waiting ui request: %1").arg(requestId));
    } else if (!m_parent->m_interactionView || !m_parent->m_interactionView->finishRequest(this)) {
        result = Result(Result::InteractionViewUnavailableError,
                        QLatin1String("Cannot finish ui request: view busy or no view registered"));
    } else {
        // don't destroy the connection yet (wait for client disconnection first)
        // but set the connection state to inactive, so that we can accept new clients.
        m_activeRequestState = InteractionService::Inactive;
        m_activeRequestId = QString();
        result = Result(Result::Succeeded);
    }
}

void InteractionService::clientDisconnected()
{
    if (!m_activeConnection.isConnected()) {
        qCDebug(lcSailfishSecretsUi) << "Active connection client disconnected from InteractionService!";
        m_activeConnection = QDBusConnection(QLatin1String("org.sailfishos.secrets.interaction.invalidConnection"));
        m_activeReply = QDBusMessage();
        m_activeRequestId = QString();
        m_activeRequestState = InteractionService::Inactive;
    }
}

// -------------- View:

namespace Sailfish {
    namespace Secrets {
        class InteractionViewPrivate : public QSharedData
        {
        public:
            InteractionViewPrivate()
                : QSharedData()
                , m_uiService(Q_NULLPTR)
                , m_secretManager(Q_NULLPTR) {}
            InteractionViewPrivate(const InteractionViewPrivate &other)
                : QSharedData(other)
                , m_uiService(other.m_uiService)
                , m_secretManager(other.m_secretManager) {}
            ~InteractionViewPrivate() {}
            QPointer<QObject> m_uiService;
            QPointer<SecretManager> m_secretManager;
        };
    } // namespace Secrets
} // namespace Sailfish

/*!
  \class InteractionView
  \brief Interface for implementing in-app authentication
  \inmodule SailfishSecrets
  \inheaderfile Secrets/interactionview.h

  If a client application wishes to use in-app authentication, they
  must instantiate an InteractionView and register it via a
  \l{Sailfish::Secrets::SecretManager}{SecretManager}.

  Subsequent flows which specify
  \l{Sailfish::Secrets::SecretManager::ApplicationInteraction}{in-app interaction}
  will be routed to the application's InteractionView.

  \note A concrete implementation of InteractionView is provided
        as \c{ApplicationInteractionView} in the \c{Sailfish.Secrets}
        QML import.
 */

/*!
  \brief Constructs a new InteractionView instance
 */
InteractionView::InteractionView()
    : d_ptr(new InteractionViewPrivate)
{
}

/*!
  \brief Constructs a copy of the \a other InteractionView instance
 */
InteractionView::InteractionView(const InteractionView &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the interaction view
 */
InteractionView::~InteractionView()
{
}

/*!
  \brief Register this view as the in-app interaction view to service
         in-app authentication flows with the \a manager.
 */
void InteractionView::registerWithSecretManager(SecretManager *manager)
{
    d_ptr->m_secretManager = manager;
    manager->registerInteractionView(this);
}

/*!
  \brief Returns a pointer to the SecretManager that this InteractionView was registered with.
 */
SecretManager *InteractionView::registeredWithSecretManager() const
{
    return d_ptr->m_secretManager.data();
}

/*!
  \brief Send the given \a response for an interaction request
 */
void InteractionView::sendResponse(
        const InteractionResponse &response)
{
    if (d_ptr->m_uiService) {
        qobject_cast<InteractionService*>(d_ptr->m_uiService)->sendResponse(response);
        d_ptr->m_uiService = Q_NULLPTR;
    }
}

/*!
  \brief Performs the specified \a request for interaction
 */
bool InteractionView::performRequest(QObject *sender, const InteractionParameters &request)
{
    if (d_ptr->m_uiService) {
        qCDebug(lcSailfishSecretsUi) << "Refusing to perform ui request: view already active with another request";
        return false;
    }

    d_ptr->m_uiService = qobject_cast<InteractionService*>(sender);
    performRequest(request);
    return true;
}

/*!
  \brief Continues the specified \a request for interaction (e.g. second stage)
 */
bool InteractionView::continueRequest(QObject *sender, const InteractionParameters &request)
{
    if (d_ptr->m_uiService) {
        qCDebug(lcSailfishSecretsUi) << "Refusing to continue ui request: view already active with another request";
        return false;
    }

    d_ptr->m_uiService = qobject_cast<InteractionService*>(sender);
    continueRequest(request);
    return true;
}

/*!
  \brief Cancels the current interaction request

  Returns true if the active request was successfully cancelled, otherwise returns false.
 */
bool InteractionView::cancelRequest(QObject *sender)
{
    if (d_ptr->m_uiService && d_ptr->m_uiService == qobject_cast<InteractionService*>(sender)) {
        d_ptr->m_uiService = Q_NULLPTR;
        cancelRequest();
        return true;
    } else if (!d_ptr->m_uiService) {
        // already canceled
        return true;
    }

    // otherwise, attempting to cancel while busy with a different request - error.
    qCDebug(lcSailfishSecretsUi) << "Refusing to cancel ui request: view already active with another request";
    return false;
}

/*!
  \brief Mark the previously-responded request as finished.

  The interaction should no longer be active, and any data associated
  with the request may be cleaned up.
 */
bool InteractionView::finishRequest(QObject *sender)
{
    if (d_ptr->m_uiService && d_ptr->m_uiService == qobject_cast<InteractionService*>(sender)) {
        qCDebug(lcSailfishSecretsUi) << "Refusing to finish active ui request: use cancel instead";
        return false;
    } else if (d_ptr->m_uiService) {
        qCDebug(lcSailfishSecretsUi) << "Refusing to finish ui request: view already active with another request";
        return false;
    }
    finishRequest();
    return true;
}
