// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "applicationinteractionview.h"
#include "applicationinteractionview_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/result.h"
#include "Secrets/interactionparameters.h"

#include <QtQml/QQmlComponent>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>

#include <QtCore/QLoggingCategory>

Q_LOGGING_CATEGORY(lcSailfishSecretsInteractionView, "org.sailfishos.secrets.interaction.view", QtWarningMsg)

using namespace Sailfish::Secrets;

/*!
  \qmltype ApplicationInteractionView
  \inqmlmodule Sailfish.Secrets
  \inherits InteractionView
*/

Plugin::ApplicationInteractionView::ApplicationInteractionView(QQuickItem *parent)
    : QQuickItem(parent), InteractionView()
    , m_childItem(Q_NULLPTR)
    , m_adapter(new Plugin::ApplicationInteractionViewPrivate(this))
{
}

Plugin::ApplicationInteractionView::~ApplicationInteractionView()
{
    if (m_childItem) {
        m_childItem->setParentItem(Q_NULLPTR);
        m_childItem->deleteLater();
    }
}

/*!
  \qmlproperty object ApplicationInteractionView::adapter
*/

QObject *Plugin::ApplicationInteractionView::adapter() const
{
    return m_adapter;
}

void Plugin::ApplicationInteractionView::setSecretManager(QObject *manager)
{
    SecretManager *secretManager = qobject_cast<SecretManager*>(manager);
    if (secretManager) {
        m_adapter->m_secretManager = secretManager;
        InteractionView::registerWithSecretManager(secretManager);
        emit secretManagerChanged();
    }
}

/*!
  \qmlproperty object ApplicationInteractionView::secretManager
*/

QObject *Plugin::ApplicationInteractionView::secretManager() const
{
    return qobject_cast<QObject*>(m_adapter->m_secretManager);
}

void Plugin::ApplicationInteractionView::parentSizeChanged()
{
    QQuickItem *parent = parentItem();
    if (parent) {
        setWidth(parent->width());
        setHeight(parent->height());
    }
}

void Plugin::ApplicationInteractionView::performRequest(const InteractionParameters &request)
{
    if (request.inputType() == InteractionParameters::UnknownInput) {
        qCWarning(lcSailfishSecretsInteractionView) << "ApplicationInteractionView unable to perform invalid request!";
        InteractionResponse response;
        response.setResult(Result(Result::InteractionViewRequestError,
                                  QStringLiteral("Unable to perform invalid request")));
        QMetaObject::invokeMethod(this, "sendResponseHelper", Qt::QueuedConnection,
                                  Q_ARG(Sailfish::Secrets::InteractionResponse, response));
        return;
    }

    QQuickItem *parent = parentItem();
    if (!parent) {
        qCWarning(lcSailfishSecretsInteractionView) << "Error creating in-process ui view: invalid parent item";
        InteractionResponse response;
        response.setResult(Result(Result::InteractionViewParentError,
                                  QStringLiteral("Invalid parent item, view cannot be shown")));
        QMetaObject::invokeMethod(this, "sendResponseHelper", Qt::QueuedConnection,
                                  Q_ARG(Sailfish::Secrets::InteractionResponse, response));
        return;
    }

    // fill the parent item
    setHeight(parent->height());
    setWidth(parent->width());
    connect(parent, &QQuickItem::widthChanged, this, &ApplicationInteractionView::parentSizeChanged);
    connect(parent, &QQuickItem::heightChanged, this, &ApplicationInteractionView::parentSizeChanged);

    // create the in-process view as a child item
    const QString overrideQml = QCoreApplication::instance()->property("Sailfish::Secrets::ApplicationInteractionView::sourceUrl").toString();
    QUrl sourceUrl(overrideQml.isEmpty() ? QStringLiteral("qrc:/defaultInteractionView.qml") : overrideQml);
    m_adapter->setInteractionParameters(request);

    qCDebug(lcSailfishSecretsInteractionView) << "Creating ApplicationInteractionView with source url:" << sourceUrl;
    QQmlComponent *component = new QQmlComponent(qmlEngine(parent), sourceUrl, parent);
    if (!component->errors().isEmpty()) {
        qCWarning(lcSailfishSecretsInteractionView) << "Error creating in-process ui view:" << component->errors();
        InteractionResponse response;
        response.setResult(Result(Result::InteractionViewError,
                                  QStringLiteral("QML file failed to compile: %1")
                                      .arg(component->errors().first().toString())));
        QMetaObject::invokeMethod(this, "sendResponseHelper", Qt::QueuedConnection,
                                  Q_ARG(Sailfish::Secrets::InteractionResponse, response));
        return;
    } else {
        QObject *childObject = component->beginCreate(qmlContext(parent));
        m_childItem = qobject_cast<QQuickItem*>(childObject);
        if (!m_childItem) {
            qCWarning(lcSailfishSecretsInteractionView) << "Error creating in-process ui view child item:" << component->errors();
            InteractionResponse response;
            response.setResult(Result(Result::InteractionViewChildError,
                                      QStringLiteral("Could not instantiate QML child item")));
            QMetaObject::invokeMethod(this, "sendResponseHelper", Qt::QueuedConnection,
                                      Q_ARG(Sailfish::Secrets::InteractionResponse, response));
            return;
        } else {
            qCDebug(lcSailfishSecretsInteractionView) << "Successfully created in-process child item with parent:"
                                                << this << "and embed parent:" << this->parent();
            m_childItem->setParent(this);
            m_childItem->setParentItem(this);
            qmlEngine(parent)->rootContext()->setContextProperty("adapter", m_adapter);
            component->completeCreate();
        }
    }
}

void Plugin::ApplicationInteractionView::continueRequest(const InteractionParameters &request)
{
    // TODO
    Q_UNUSED(request)
}

void Plugin::ApplicationInteractionView::cancelRequest()
{
    if (m_childItem) {
        m_childItem->deleteLater();
        m_childItem = 0;
    }
    emit canceled();
}

void Plugin::ApplicationInteractionView::finishRequest()
{
    if (m_childItem) {
        m_childItem->deleteLater();
        m_childItem = 0;
    }
    emit finished();
}


Plugin::ApplicationInteractionViewPrivate::ApplicationInteractionViewPrivate(ApplicationInteractionView *parent)
    : QObject(parent)
    , m_parent(parent)
    , m_secretManager(Q_NULLPTR)
    , m_confirmation(Plugin::ApplicationInteractionView::Unknown)
    , m_ready(false)
{
}

void Plugin::ApplicationInteractionViewPrivate::sendResponse(bool confirmed)
{
    InteractionResponse response;
    response.setResult(Result(Result::Succeeded));
    response.setResponseData(confirmed ? QByteArray("true") : QByteArray());
    QMetaObject::invokeMethod(m_parent, "sendResponseHelper", Qt::QueuedConnection,
                              Q_ARG(Sailfish::Secrets::InteractionResponse, response));
}

void Plugin::ApplicationInteractionViewPrivate::sendResponse(const QByteArray &userInput)
{
    InteractionResponse response;
    response.setResult(Result(Result::Succeeded));
    response.setResponseData(userInput);
    QMetaObject::invokeMethod(m_parent, "sendResponseHelper", Qt::QueuedConnection,
                              Q_ARG(Sailfish::Secrets::InteractionResponse, response));
}

// Helper slot which can be invoked via QueuedConnection.
void Sailfish::Secrets::Plugin::ApplicationInteractionView::sendResponseHelper(
        const Sailfish::Secrets::InteractionResponse &response)
{
    Sailfish::Secrets::InteractionView::sendResponse(response);
}

