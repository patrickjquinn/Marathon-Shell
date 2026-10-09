// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef SAILFISHSECRETS_QML_APPLICATIONINTERACTIONVIEW_P_H
#define SAILFISHSECRETS_QML_APPLICATIONINTERACTIONVIEW_P_H

#include "applicationinteractionview.h"

#include "Secrets/secretmanager.h"
#include "Secrets/interactionparameters.h"

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QUrl>

#include <QtDebug>

namespace Sailfish {

namespace Secrets {

namespace Plugin {

// We have a variety of different possible user interaction flows.
// See the different InteractionParameters::InputTypes for data we
// can request from the user.
// See the different InteractionParameters::Operations for operations
// we can request permission from the user for.

class ApplicationInteractionView;
class ApplicationInteractionViewPrivate : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int confirmation READ confirmation WRITE setConfirmation NOTIFY confirmationChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(InteractionParameters interactionParameters READ interactionParameters NOTIFY interactionParametersChanged)

public:
    ApplicationInteractionViewPrivate(ApplicationInteractionView *parent = Q_NULLPTR);

    int confirmation() const { return m_confirmation; }
    void setConfirmation(int v) {
        if (m_confirmation != v) {
            m_confirmation = v;
            emit confirmationChanged();
            if (m_ready) {
                sendResponse(v == Sailfish::Secrets::Plugin::ApplicationInteractionView::Allow);
                m_confirmation = Sailfish::Secrets::Plugin::ApplicationInteractionView::Unknown; // reset.
            }
        }
    }

    QString password() const { return m_password; }
    void setPassword(const QString &v) {
        if (m_password != v) {
            m_password = v;
            emit passwordChanged();
            if (m_ready) {
                sendResponse(v.toUtf8());
                m_password.clear(); // reset.
            }
        }
    }

    Sailfish::Secrets::InteractionParameters interactionParameters() const { return m_request; }
    void setInteractionParameters(const Sailfish::Secrets::InteractionParameters &request) {
        m_ready = true;
        m_request = request;
        emit interactionParametersChanged();
    }

Q_SIGNALS:
    void confirmationChanged();
    void passwordChanged();
    void interactionParametersChanged();

private Q_SLOTS:
    void sendResponse(bool confirmed);
    void sendResponse(const QByteArray &authenticationCode);

private:
    friend class ApplicationInteractionView;
    ApplicationInteractionView *m_parent;
    SecretManager *m_secretManager;
    InteractionParameters m_request;
    QString m_password;
    int m_confirmation;
    bool m_ready;
};

} // namespace Plugin

} // namespace Secrets

} // namespace Sailfish

#endif // SAILFISHSECRETS_QML_APPLICATIONINTERACTIONVIEW_P_H
