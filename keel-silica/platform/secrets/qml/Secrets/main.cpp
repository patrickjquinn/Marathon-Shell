// SPDX-FileCopyrightText: 2017-2020 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 - 2020 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "plugintypes.h"
#include "applicationinteractionview.h"
#include "findsecretsrequestwrapper.h"

#include <QtQml/QQmlEngine>
#include <QtQml>

// Modified by Shipwright for Qt 6: Qt 6 refuses value (gadget) types under
// upper-case QML names. The gadget's enums are registered under the
// documented name (Result.Succeeded and so on), the value type under the
// same name in lower case (used for property access only).
template <typename T>
static void keelRegisterGadget(const char *uri, const char *name, const QString &reason)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    qmlRegisterUncreatableMetaObject(T::staticMetaObject, uri, 1, 0, name, reason);
    static QList<QByteArray> lowerNames; // QML keeps the name pointer
    QByteArray lower(name);
    lower[0] = char(QChar::toLower(uchar(lower.at(0))));
    lowerNames.append(lower);
    qmlRegisterUncreatableType<T>(uri, 1, 0, lowerNames.last().constData(), reason);
#else
    qmlRegisterUncreatableType<T>(uri, 1, 0, name, reason);
#endif
}

void Sailfish::Secrets::Plugin::SecretsPlugin::initializeEngine(QQmlEngine *, const char *)
{
}

void Sailfish::Secrets::Plugin::SecretsPlugin::registerTypes(const char *uri)
{
    qRegisterMetaType<Sailfish::Secrets::InteractionParameters>("Sailfish::Secrets::InteractionParameters");
    qRegisterMetaType<Sailfish::Secrets::InteractionParameters::InputType>("Sailfish::Secrets::InteractionParameters::InputType");
    qRegisterMetaType<Sailfish::Secrets::InteractionParameters::EchoMode>("Sailfish::Secrets::InteractionParameters::EchoMode");
    qRegisterMetaType<Sailfish::Secrets::InteractionParameters::Operation>("Sailfish::Secrets::InteractionParameters::Operation");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Secrets::InteractionParameters>();
#endif
    keelRegisterGadget<Sailfish::Secrets::InteractionParameters>(uri, "InteractionParameters", QStringLiteral("InteractionParameters objects cannot be constructed directly in QML"));
    keelRegisterGadget<Sailfish::Secrets::InteractionParameters::PromptText>(uri, "PromptText", QStringLiteral("Can't construct PromptText in QML"));

    qRegisterMetaType<Sailfish::Secrets::InteractionResponse>("Sailfish::Secrets::InteractionResponse");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Secrets::InteractionResponse>();
#endif
    keelRegisterGadget<Sailfish::Secrets::InteractionResponse>(uri, "InteractionResponse", QStringLiteral("InteractionResponse objects cannot be constructed directly in QML"));

    qRegisterMetaType<Sailfish::Secrets::Result>("Sailfish::Secrets::Result");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Secrets::Result>();
#endif
    keelRegisterGadget<Sailfish::Secrets::Result>(uri, "Result", QStringLiteral("Result objects cannot be constructed directly in QML"));
    qRegisterMetaType<Sailfish::Secrets::Result::ResultCode>("Sailfish::Secrets::Result::ResultCode");
    qRegisterMetaType<Sailfish::Secrets::Result::ErrorCode>("Sailfish::Secrets::Result::ErrorCode");

    qRegisterMetaType<Sailfish::Secrets::Secret>("Sailfish::Secrets::Secret");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Secrets::Secret>();
#endif
    keelRegisterGadget<Sailfish::Secrets::Secret>(uri, "Secret", QStringLiteral("Secret objects cannot be constructed directly in QML"));

    qmlRegisterUncreatableType<Sailfish::Secrets::Request>(uri, 1, 0, "Request", QStringLiteral("Request is an abstract class, can't construct in QML"));
    qRegisterMetaType<Sailfish::Secrets::Request::Status>("Sailfish::Secrets::Request::Status");
    keelRegisterGadget<Sailfish::Secrets::PluginInfo>(uri, "PluginInfo", QStringLiteral("PluginInfo objects cannot be constructed directly in QML"));
    qmlRegisterType<Sailfish::Secrets::Plugin::PluginInfoRequestWrapper>(uri, 1, 0, "PluginInfoRequest");
    qmlRegisterType<Sailfish::Secrets::HealthCheckRequest>(uri, 1, 0, "HealthCheckRequest");
    qmlRegisterType<Sailfish::Secrets::CollectionNamesRequest>(uri, 1, 0, "CollectionNamesRequest");
    qmlRegisterType<Sailfish::Secrets::CreateCollectionRequest>(uri, 1, 0, "CreateCollectionRequest");
    qmlRegisterType<Sailfish::Secrets::DeleteCollectionRequest>(uri, 1, 0, "DeleteCollectionRequest");
    qmlRegisterType<Sailfish::Secrets::StoreSecretRequest>(uri, 1, 0, "StoreSecretRequest");
    qmlRegisterType<Sailfish::Secrets::StoredSecretRequest>(uri, 1, 0, "StoredSecretRequest");
    qmlRegisterType<Sailfish::Secrets::Plugin::FindSecretsRequestWrapper>(uri, 1, 0, "FindSecretsRequest");
    qmlRegisterType<Sailfish::Secrets::DeleteSecretRequest>(uri, 1, 0, "DeleteSecretRequest");
    qmlRegisterType<Sailfish::Secrets::InteractionRequest>(uri, 1, 0, "InteractionRequest");
    qmlRegisterType<Sailfish::Secrets::LockCodeRequest>(uri, 1, 0, "LockCodeRequest");

    qmlRegisterType<Sailfish::Secrets::Plugin::ApplicationInteractionView>(uri, 1, 0, "ApplicationInteractionView");
    qmlRegisterType<Sailfish::Secrets::Plugin::SecretManager>(uri, 1, 0, "SecretManager");
}

/*!
  \qmltype SecretManager
  \brief Allows clients to make requests of the system secrets service.
  \inqmlmodule Sailfish.Secrets
*/

Sailfish::Secrets::Plugin::SecretManager::SecretManager(QObject *parent)
    : Sailfish::Secrets::SecretManager(parent)
{
}

Sailfish::Secrets::Plugin::SecretManager::~SecretManager()
{
}

/*!
  \qmlproperty string SecretManager::inAppAuthenticationPluginName
 */

QString Sailfish::Secrets::Plugin::SecretManager::inAppAuthenticationPluginName() const
{
    return InAppAuthenticationPluginName;
}

/*!
  \qmlproperty string SecretManager::defaultAuthenticationPluginName
 */

QString Sailfish::Secrets::Plugin::SecretManager::defaultAuthenticationPluginName() const
{
    return DefaultAuthenticationPluginName;
}

/*!
  \qmlproperty string SecretManager::defaultStoragePluginName
 */

QString Sailfish::Secrets::Plugin::SecretManager::defaultStoragePluginName() const
{
    return DefaultStoragePluginName;
}

/*!
  \qmlproperty string SecretManager::defaultEncryptionPluginName
 */

QString Sailfish::Secrets::Plugin::SecretManager::defaultEncryptionPluginName() const
{
    return DefaultEncryptionPluginName;
}

/*!
  \qmlproperty string SecretManager::defaultEncryptedStoragePluginName
 */

QString Sailfish::Secrets::Plugin::SecretManager::defaultEncryptedStoragePluginName() const
{
    return DefaultEncryptedStoragePluginName;
}

/*!
  \qmlmethod Result SecretManager::constructResult()
*/

Sailfish::Secrets::Result Sailfish::Secrets::Plugin::SecretManager::constructResult() const
{
    return Sailfish::Secrets::Result();
}

/*!
  \qmlmethod Secret SecretManager::constructSecret()
*/

Sailfish::Secrets::Secret Sailfish::Secrets::Plugin::SecretManager::constructSecret() const
{
    return Sailfish::Secrets::Secret();
}

/*!
  \qmlmethod InteractionParameters SecretManager::constructInteractionParameters()
*/

Sailfish::Secrets::InteractionParameters Sailfish::Secrets::Plugin::SecretManager::constructInteractionParameters() const
{
    return Sailfish::Secrets::InteractionParameters();
}

/*!
  \qmlmethod InteractionResponse SecretManager::constructInteractionResponse()
*/

Sailfish::Secrets::InteractionResponse Sailfish::Secrets::Plugin::SecretManager::constructInteractionResponse() const
{
    return Sailfish::Secrets::InteractionResponse();
}

/*!
  \qmlmethod FilterData SecretManager::constructFilterData(object v)
*/

Sailfish::Secrets::Secret::FilterData Sailfish::Secrets::Plugin::SecretManager::constructFilterData(const QVariantMap &v) const
{
    Sailfish::Secrets::Secret::FilterData filter;
    for (QVariantMap::ConstIterator it = v.constBegin();
         it != v.constEnd(); it++) {
        const QString &value = it->toString();
        if (!value.isEmpty()) {
            filter.insert(it.key(), value);
        }
    }
    return filter;
}

/*!
  \qmlmethod string SecretManager::toBase64(ArrayBuffer data)
*/

QString Sailfish::Secrets::Plugin::SecretManager::toBase64(const QByteArray &data) const
{
    return QString::fromUtf8(data.toBase64(QByteArray::KeepTrailingEquals | QByteArray::Base64UrlEncoding));
}

/*!
  \qmlmethod ArrayBuffer SecretManager::fromBase64(string b64)
*/

QByteArray Sailfish::Secrets::Plugin::SecretManager::fromBase64(const QString &b64) const
{
    return b64.toUtf8().fromBase64(b64.toUtf8(), QByteArray::KeepTrailingEquals | QByteArray::Base64UrlEncoding);
}

/*!
  \qmlmethod string SecretManager::stringFromBytes(ArrayBuffer stringData)
*/

QString Sailfish::Secrets::Plugin::SecretManager::stringFromBytes(const QByteArray &stringData) const
{
    return QString::fromUtf8(stringData);
}

