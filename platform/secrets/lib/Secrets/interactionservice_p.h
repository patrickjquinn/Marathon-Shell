// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_INTERACTIONSERVICE_P_H
#define LIBSAILFISHSECRETS_INTERACTIONSERVICE_P_H

#include "Secrets/secretmanager_p.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/result.h"

#include <QtDBus/QDBusServer>
#include <QtDBus/QDBusContext>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCallWatcher>

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtCore/QList>
#include <QtCore/QString>

namespace Sailfish {

namespace Secrets {

class SecretManagerPrivate;

/*
 *  The InteractionService instance lives within the client process.
 *  It is instantiated if the client attempts to perform a secrets request
 *  with the UserInteractionMode set to ApplicationInteraction.
 *  It talks to the sailfishsecretsd via P2P DBus connection, and triggers
 *  interaction within the InteractionView registered with the manager.
 */
class SAILFISH_SECRETS_API InteractionService : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.secrets.interaction")
    Q_CLASSINFO("D-Bus Introspection", ""
    "  <interface name=\"org.sailfishos.secrets.interaction\">\n"
    "      <method name=\"performInteractionRequest\">\n"
    "          <arg name=\"request\" type=\"(ssss(i)sa{is}(i)(i))\" direction=\"in\" />\n"
    "          <arg name=\"response\" type=\"((iis)ay)\" direction=\"out\" />\n"
    "          <arg name=\"requestId\" type=\"s\" direction=\"out\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.In0\" value=\"Sailfish::Secrets::InteractionParameters\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"Sailfish::Secrets::InteractionResponse\" />\n"
    "      </method>\n"
    "      <method name=\"continueInteractionRequest\">\n"
    "          <arg name=\"requestId\" type=\"s\" direction=\"in\" />\n"
    "          <arg name=\"request\" type=\"(ssss(i)sa{is}(i)(i))\" direction=\"in\" />\n"
    "          <arg name=\"response\" type=\"((iis)ay)\" direction=\"out\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.In1\" value=\"Sailfish::Secrets::InteractionParameters\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"Sailfish::Secrets::InteractionResponse\" />\n"
    "      </method>\n"
    "      <method name=\"cancelInteractionRequest\">\n"
    "          <arg name=\"requestId\" type=\"s\" direction=\"in\" />\n"
    "          <arg name=\"result\" type=\"(iis)\" direction=\"out\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"Sailfish::Secrets::Result\" />\n"
    "      </method>\n"
    "      <method name=\"finishInteractionRequest\">\n"
    "          <arg name=\"requestId\" type=\"s\" direction=\"in\" />\n"
    "          <arg name=\"result\" type=\"(iis)\" direction=\"out\" />\n"
    "          <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"Sailfish::Secrets::Result\" />\n"
    "      </method>\n"
    "  </interface>\n"
    "")

public:
    InteractionService(SecretManagerPrivate *parent = Q_NULLPTR);
    QString address() const { return m_address; }
    bool registerServer();
    void sendResponse(const Sailfish::Secrets::InteractionResponse &response);

public Q_SLOTS:
    void performInteractionRequest(const Sailfish::Secrets::InteractionParameters &request,
                          const QDBusMessage &message,
                          Sailfish::Secrets::InteractionResponse &response,
                          QString &requestId);
    void continueInteractionRequest(const QString &requestId,
                           const Sailfish::Secrets::InteractionParameters &request,
                           const QDBusMessage &message,
                           Sailfish::Secrets::InteractionResponse &response);
    void cancelInteractionRequest(const QString &requestId,
                         const QDBusMessage &message,
                         Sailfish::Secrets::Result &result);
    void finishInteractionRequest(const QString &requestId,
                         const QDBusMessage &message,
                         Sailfish::Secrets::Result &result);

private Q_SLOTS:
    void clientDisconnected();

private:
    SecretManagerPrivate *m_parent;
    QDBusServer *m_dbusServer;
    QString m_address;

    QDBusConnection m_activeConnection;
    QDBusMessage m_activeReply;
    QString m_activeRequestId;
    enum ActiveRequestState {
        Inactive = 0,
        Started,
        Waiting
    };
    ActiveRequestState m_activeRequestState;
    int m_connectedClients;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_INTERACTIONSERVICE_P_H
