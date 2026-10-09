// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/interactionrequestwatcher.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/interactionresponse.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusServer>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>

Q_LOGGING_CATEGORY(lcSailfishSecretsInteractionServiceConnection, "org.sailfishos.secrets.interactionservice.connection", QtWarningMsg)

namespace Sailfish {

namespace Secrets {

class InteractionRequestWatcherPrivate
{
public:
    InteractionRequestWatcherPrivate()
        : m_watcher(Q_NULLPTR)
        , m_interface(Q_NULLPTR)
        , m_connection(QLatin1String("org.sailfishos.secrets.interaction.invalidConnection"))
        , m_requestId(0)
        , m_callerPid(0)
    {
    }

    QDBusPendingCallWatcher *m_watcher;
    QDBusInterface *m_interface;
    QDBusConnection m_connection;

    quint64 m_requestId;
    pid_t m_callerPid;
    InteractionParameters m_request;
    QString m_interactionServiceAddress;
    QString m_uiRequestId;
};

} // namespace Secrets

} // namespace Sailfish

using namespace Sailfish::Secrets;

InteractionRequestWatcher::InteractionRequestWatcher(QObject *parent)
    : QObject(parent)
    , m_data(new InteractionRequestWatcherPrivate)
{
}

InteractionRequestWatcher::~InteractionRequestWatcher()
{
    delete m_data;
}

void InteractionRequestWatcher::setRequestId(quint64 id)
{
    m_data->m_requestId = id;
}

void InteractionRequestWatcher::setCallerPid(pid_t pid)
{
    m_data->m_callerPid = pid;
}

void InteractionRequestWatcher::setInteractionParameters(const InteractionParameters &request)
{
    m_data->m_request = request;
}

void InteractionRequestWatcher::setInteractionServiceAddress(const QString &address)
{
    m_data->m_interactionServiceAddress = address;
}

quint64 InteractionRequestWatcher::requestId() const
{
    return m_data->m_requestId;
}

pid_t InteractionRequestWatcher::callerPid() const
{
    return m_data->m_callerPid;
}

InteractionParameters InteractionRequestWatcher::interactionParameters() const
{
    return m_data->m_request;
}

QString InteractionRequestWatcher::interactionServiceAddress() const
{
    return m_data->m_interactionServiceAddress;
}

bool InteractionRequestWatcher::connectToInteractionService()
{
    const QString name = QString::fromLatin1("sailfishsecretsd-ui-connection-%1").arg(m_data->m_requestId);

    qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Connecting to ui service via p2p address:"
                                                           << m_data->m_interactionServiceAddress
                                                           << "with connection name:" << name;

    QDBusConnection p2pc = QDBusConnection::connectToPeer(m_data->m_interactionServiceAddress, name);
    if (!p2pc.isConnected()) {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Unable to connect to ui service:"
                                                        << p2pc.lastError()
                                                        << p2pc.lastError().type()
                                                        << p2pc.lastError().name();
        return false;
    }

    m_data->m_connection = p2pc;
    m_data->m_connection.connect(
            QString(), // any service
            QString::fromUtf8("/org/freedesktop/DBus/Local"),
            QString::fromUtf8("org.freedesktop.DBus.Local"),
            QString::fromUtf8("Disconnected"),
            this, SLOT(interactionServiceDisconnected()));

    m_data->m_interface = new QDBusInterface(
            QLatin1String("org.sailfishos.secrets.interaction"),
            QLatin1String("/"),
            QLatin1String("org.sailfishos.secrets.interaction"),
            m_data->m_connection,
            this);

    m_data->m_interface->setTimeout(120000); // 2 minutes timeout.  Sign-on flows require user input.
    qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Connected to Ui service:" << m_data->m_connection.name();
    return true;
}

bool InteractionRequestWatcher::sendInteractionRequest()
{
    if (m_data->m_watcher) {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Not sending Ui request: outstanding request in progress";
        return false; // outstanding request in progress!
    }

    // send the request, and instantiate the watcher to watch it.
    m_data->m_watcher = new QDBusPendingCallWatcher(m_data->m_interface->asyncCall(
                                                        "performInteractionRequest",
                                                        QVariant::fromValue<Sailfish::Secrets::InteractionParameters>(interactionParameters())),
                                                    this);

    connect(m_data->m_watcher, &QDBusPendingCallWatcher::finished,
            this, static_cast<void (InteractionRequestWatcher::*)(void)>(&InteractionRequestWatcher::interactionRequestFinished));

    return true;
}

bool InteractionRequestWatcher::continueInteractionRequest(const InteractionParameters &request)
{
    if (!m_data->m_watcher || m_data->m_uiRequestId.isEmpty()) {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Not continuing Ui request: no outstanding request in progress";
        return false; // no outstanding request in progress!
    }

    // send the request, and instantiate the watcher to watch it.
    m_data->m_watcher = new QDBusPendingCallWatcher(m_data->m_interface->asyncCall(
                                                        "continueInteractionRequest",
                                                        QVariant::fromValue<QString>(m_data->m_uiRequestId),
                                                        QVariant::fromValue<InteractionParameters>(request)),
                                                    this);

    connect(m_data->m_watcher, &QDBusPendingCallWatcher::finished,
            this, &InteractionRequestWatcher::interactionContinuationRequestFinished);

    return true;
}

bool InteractionRequestWatcher::cancelInteractionRequest()
{
    if (!m_data->m_watcher || m_data->m_uiRequestId.isEmpty()) {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Not canceling Ui request: no outstanding request in progress";
        return false; // no outstanding request in progress!
    }

    // send the request, and instantiate the watcher to watch it.
    m_data->m_watcher = new QDBusPendingCallWatcher(m_data->m_interface->asyncCall(
                                                        "cancelInteractionRequest",
                                                        QVariant::fromValue<QString>(m_data->m_uiRequestId)),
                                                    this);

    connect(m_data->m_watcher, &QDBusPendingCallWatcher::finished,
            this, &InteractionRequestWatcher::interactionCancelFinished);

    return true;
}

bool InteractionRequestWatcher::finishInteractionRequest()
{
    if (!m_data->m_watcher || m_data->m_uiRequestId.isEmpty()) {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Not finishing Ui request: no outstanding request in progress";
        return false; // no outstanding request in progress!
    }

    // send the request, and instantiate the watcher to watch it.
    m_data->m_watcher = new QDBusPendingCallWatcher(m_data->m_interface->asyncCall(
                                                        "finishInteractionRequest",
                                                        QVariant::fromValue<QString>(m_data->m_uiRequestId)),
                                                    this);

    connect(m_data->m_watcher, &QDBusPendingCallWatcher::finished,
            this, &InteractionRequestWatcher::interactionFinishFinished);

    return true;
}

void InteractionRequestWatcher::interactionRequestFinished()
{
    QDBusPendingReply<InteractionResponse, QString> reply = *m_data->m_watcher;
    reply.waitForFinished();
    if (reply.isValid()) {
        InteractionResponse response = reply.argumentAt<0>();
        m_data->m_uiRequestId = reply.argumentAt<1>();
        if (response.result().code() != Result::Succeeded) {
            qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Ui request returned error:" << response.result().errorMessage();
        }
        emit interactionRequestResponse(m_data->m_requestId, response);
    } else {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Invalid response to Ui request!";
        QString errorMessage = reply.isError() ? reply.error().message() : QLatin1String("Invalid response to Ui request");
        InteractionResponse errorResponse;
        errorResponse.setResult(Result(Result::InteractionServiceResponseInvalidError, errorMessage));
        emit interactionRequestResponse(m_data->m_requestId, errorResponse);
    }
}

void InteractionRequestWatcher::interactionContinuationRequestFinished()
{
    QDBusPendingReply<InteractionResponse> reply = *m_data->m_watcher;
    reply.waitForFinished();
    if (reply.isValid()) {
        InteractionResponse response = reply.argumentAt<0>();
        if (response.result().code() != Result::Succeeded) {
            qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Ui continuation request returned error:" << response.result().errorMessage();
        }
        emit interactionRequestResponse(m_data->m_requestId, response);
    } else {
        qCWarning(lcSailfishSecretsInteractionServiceConnection) << "Invalid response to Ui continuation request!";
        QString errorMessage = reply.isError() ? reply.error().message() : QLatin1String("Invalid response to Ui continuation request");
        InteractionResponse errorResponse;
        errorResponse.setResult(Result(Result::InteractionServiceResponseInvalidError, errorMessage));
        emit interactionRequestResponse(m_data->m_requestId, errorResponse);
    }
}

void InteractionRequestWatcher::interactionCancelFinished()
{
    QDBusPendingReply<Result> reply = *m_data->m_watcher;
    if (reply.isValid()) {
        qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Canceled Ui request.";
    } else {
        qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Unable to cleanly cancel Ui request!";
    }
    emit interactionRequestFinished(m_data->m_requestId);
}

void InteractionRequestWatcher::interactionFinishFinished()
{
    QDBusPendingReply<Result> reply = *m_data->m_watcher;
    if (reply.isValid()) {
        qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Finished Ui request.";
    } else {
        qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Unable to cleanly finish Ui request!";
    }
    emit interactionRequestFinished(m_data->m_requestId);
}

void InteractionRequestWatcher::interactionServiceDisconnected()
{
    qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Disconnected from Ui service:" << m_data->m_connection.name();
    // TODO: uncomment me?  depends on which event we receive first...
    //emit interactionRequestResponse(m_data->m_requestId,
    //                       Result(Result::ErrorOccurred, "Disconnected from Ui service"),
    //                       InteractionResponse());
}

void InteractionRequestWatcher::disconnectFromInteractionService()
{
    qCDebug(lcSailfishSecretsInteractionServiceConnection) << "Finished sign-on-ui session, disconnecting from service:" << m_data->m_connection.name();
    QDBusConnection::disconnectFromPeer(m_data->m_connection.name());
    m_data->m_connection = QDBusConnection(QLatin1String("org.sailfishos.accounts.signonui.invalidConnection"));
}
