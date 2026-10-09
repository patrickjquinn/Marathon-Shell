// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"
#include "Secrets/secret.h"
#include "Secrets/plugininfo.h"

#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusMetaType>

#include <QtCore/QPointer>
#include <QtCore/QLoggingCategory>
#include <QtCore/QStandardPaths>
#include <QtCore/QDir>

Q_LOGGING_CATEGORY(lcSailfishSecrets, "org.sailfishos.secrets", QtWarningMsg)

using namespace Sailfish::Secrets;

const QString Secret::FilterDataFieldType = QStringLiteral("Type");
const QString Secret::TypeUnknown = QStringLiteral("Unknown");
const QString Secret::TypeBlob = QStringLiteral("Blob");
const QString Secret::TypeCryptoKey = QStringLiteral("CryptoKey"); // Do not change this without updating Crypto::Key.cpp
const QString Secret::TypeCryptoCertificate = QStringLiteral("CryptoCertificate");
const QString Secret::TypeUsernamePassword = QStringLiteral("UsernamePassword");

const QString SecretManager::InAppAuthenticationPluginName = QStringLiteral("plugin.authentication.inapp");
const QString SecretManager::DefaultAuthenticationPluginName = QStringLiteral("plugin.authentication.default");
const QString SecretManager::DefaultStoragePluginName = QStringLiteral("plugin.storage.default");
const QString SecretManager::DefaultEncryptionPluginName = QStringLiteral("plugin.encryption.default");
const QString SecretManager::DefaultEncryptedStoragePluginName = QStringLiteral("plugin.encryptedstorage.default");

/*!
  \class SecretManagerPrivate
  \internal
  \brief Encapsulates DBus communication with the system secrets service
  \inmodule SailfishSecrets
 */

/*!
  \internal
 */
SecretManagerPrivate::SecretManagerPrivate(SecretManager *parent)
    : QObject(parent)
    , m_uiService(Q_NULLPTR)
    , m_interactionView(Q_NULLPTR)
    , m_secrets(SecretsDaemonConnection::instance())
    , m_interface(m_secrets->connect()
                  ? m_secrets->createInterface(QLatin1String("/Sailfish/Secrets"), QLatin1String("org.sailfishos.secrets"), this)
                  : Q_NULLPTR)
{
}

SecretManagerPrivate::~SecretManagerPrivate()
{
    SecretsDaemonConnection::releaseInstance();
    m_interface = Q_NULLPTR;
}

Result
SecretManagerPrivate::registerInteractionService(
        SecretManager::UserInteractionMode mode,
        QString *address)
{
    if (mode == SecretManager::ApplicationInteraction) {
        if (!m_uiService) {
            m_uiService = new InteractionService(this);
        }
        if (!m_uiService->registerServer()) {
            Result result(Result::InteractionServiceUnavailableError,
                                             QStringLiteral("Unable to start in-process ui service"));
            return result;
        }
        *address = m_uiService->address();
    } else {
        *address = QString();
    }
    return Result(Result::Succeeded);
}

QDBusPendingReply<Result,
                  QVector<PluginInfo>,
                  QVector<PluginInfo>,
                  QVector<PluginInfo>,
                  QVector<PluginInfo> >
SecretManagerPrivate::getPluginInfo()
{
    if (!m_interface) {
        return QDBusPendingReply<Result,
                                 QVector<PluginInfo>,
                                 QVector<PluginInfo>,
                                 QVector<PluginInfo>,
                                 QVector<PluginInfo> >(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result,
                      QVector<PluginInfo>,
                      QVector<PluginInfo>,
                      QVector<PluginInfo>,
                      QVector<PluginInfo> > reply
            = m_interface->asyncCall(QStringLiteral("getPluginInfo"));
    return reply;
}


QDBusPendingReply<Sailfish::Secrets::Result,
                  HealthCheckRequest::Health,
                  HealthCheckRequest::Health>
SecretManagerPrivate::getHealthInfo()
{
    if (!m_interface) {
        return QDBusPendingReply<Sailfish::Secrets::Result,
                                 HealthCheckRequest::Health,
                                 HealthCheckRequest::Health>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Sailfish::Secrets::Result,
                      HealthCheckRequest::Health,
                      HealthCheckRequest::Health> reply
            = m_interface->asyncCall(QStringLiteral("getHealthInfo"));
    return reply;
}

QDBusPendingReply<Result, QByteArray>
SecretManagerPrivate::userInput(
        const InteractionParameters &uiParams)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("userInput"),
                QVariantList() << QVariant::fromValue<InteractionParameters>(uiParams));
    return reply;
}


QDBusPendingReply<Result, QMap<QString, bool> >
SecretManagerPrivate::collectionNames(
        const QString &storagePluginName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QMap<QString, bool> >(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QMap<QString, bool> > reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("collectionNames"),
                QVariantList() << QVariant::fromValue<QString>(storagePluginName));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::createCollection(
        const QString &collectionName,
        const QString &storagePluginName,
        const QString &encryptionPluginName,
        SecretManager::DeviceLockUnlockSemantic unlockSemantic,
        SecretManager::AccessControlMode accessControlMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("createCollection"),
                QVariantList() << QVariant::fromValue<QString>(collectionName)
                               << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<QString>(encryptionPluginName)
                               << QVariant::fromValue<SecretManager::DeviceLockUnlockSemantic>(unlockSemantic)
                               << QVariant::fromValue<SecretManager::AccessControlMode>(accessControlMode));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::createCollection(
        const QString &collectionName,
        const QString &storagePluginName,
        const QString &encryptionPluginName,
        const QString &authenticationPluginName,
        SecretManager::CustomLockUnlockSemantic unlockSemantic,
        SecretManager::AccessControlMode accessControlMode,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("createCollection"),
                QVariantList() << QVariant::fromValue<QString>(collectionName)
                               << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<QString>(encryptionPluginName)
                               << QVariant::fromValue<QString>(authenticationPluginName)
                               << QVariant::fromValue<SecretManager::CustomLockUnlockSemantic>(unlockSemantic)
                               << QVariant::fromValue<SecretManager::AccessControlMode>(accessControlMode)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::deleteCollection(
        const QString &collectionName,
        const QString &storagePluginName,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("deleteCollection"),
                QVariantList() << QVariant::fromValue<QString>(collectionName)
                               << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::setSecret(
        const Secret &secret,
        const InteractionParameters &uiParams,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (!secret.identifier().isValid() || secret.identifier().identifiesStandaloneSecret()) {
        Result identifierError(Result::InvalidSecretIdentifierError,
                               QLatin1String("This method cannot be invoked with a standalone secret"));
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(identifierError)));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("setSecret"),
                QVariantList() << QVariant::fromValue<Secret>(secret)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::setSecret(
        const Secret &secret,
        const QString &encryptionPluginName,
        const InteractionParameters &uiParams,
        SecretManager::DeviceLockUnlockSemantic unlockSemantic,
        SecretManager::AccessControlMode accessControlMode,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (!secret.identifier().isValid() || !secret.identifier().identifiesStandaloneSecret()) {
        Result identifierError(Result::InvalidSecretIdentifierError,
                               QLatin1String("This method cannot be invoked with a collection secret"));
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(identifierError)));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("setSecret"),
                QVariantList() << QVariant::fromValue<Secret>(secret)
                               << QVariant::fromValue<QString>(encryptionPluginName)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<SecretManager::DeviceLockUnlockSemantic>(unlockSemantic)
                               << QVariant::fromValue<SecretManager::AccessControlMode>(accessControlMode)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::setSecret(
        const Secret &secret,
        const QString &encryptionPluginName,
        const QString &authenticationPluginName,
        const InteractionParameters &uiParams,
        SecretManager::CustomLockUnlockSemantic unlockSemantic,
        SecretManager::AccessControlMode accessControlMode,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (!secret.identifier().isValid() || !secret.identifier().identifiesStandaloneSecret()) {
        Result identifierError(Result::InvalidSecretIdentifierError,
                               QLatin1String("This method cannot be invoked with a collection secret"));
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(identifierError)));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("setSecret"),
                QVariantList() << QVariant::fromValue<Secret>(secret)
                               << QVariant::fromValue<QString>(encryptionPluginName)
                               << QVariant::fromValue<QString>(authenticationPluginName)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<SecretManager::CustomLockUnlockSemantic>(unlockSemantic)
                               << QVariant::fromValue<SecretManager::AccessControlMode>(accessControlMode)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result, Secret>
SecretManagerPrivate::getSecret(
        const Secret::Identifier &identifier,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (!identifier.isValid()) {
        Result identifierError(Result::InvalidSecretIdentifierError,
                               QLatin1String("The given identifier is invalid"));
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(identifierError)));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result, Secret> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("getSecret"),
                QVariantList() << QVariant::fromValue<Secret::Identifier>(identifier)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result, QVector<Secret::Identifier> >
SecretManagerPrivate::findSecrets(
        const QString &collectionName,
        const QString &storagePluginName,
        const Secret::FilterData &filter,
        SecretManager::FilterOperator filterOperator,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QVector<Secret::Identifier> >(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (collectionName.isEmpty()) {
        Result collectionError(Result::InvalidCollectionError,
                               QLatin1String("The given collection name is invalid"));
        return QDBusPendingReply<Result, QVector<Secret::Identifier> >(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(collectionError)
                                       << QVariant::fromValue<QVector<Secret::Identifier> >(QVector<Secret::Identifier>())));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result, QVector<Secret::Identifier> >(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)
                                       << QVariant::fromValue<QVector<Secret::Identifier> >(QVector<Secret::Identifier>())));
    }

    QDBusPendingReply<Result, QVector<Secret::Identifier> > reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("findSecrets"),
                QVariantList() << QVariant::fromValue<QString>(collectionName)
                               << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<Secret::FilterData>(filter)
                               << QVariant::fromValue<SecretManager::FilterOperator>(filterOperator)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result, QVector<Secret::Identifier> >
SecretManagerPrivate::findSecrets(
        const QString &storagePluginName,
        const Secret::FilterData &filter,
        SecretManager::FilterOperator filterOperator,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result, Secret> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("findSecrets"),
                QVariantList() << QVariant::fromValue<QString>(QString())
                               << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<Secret::FilterData>(filter)
                               << QVariant::fromValue<SecretManager::FilterOperator>(filterOperator)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::deleteSecret(
        const Secret::Identifier &identifier,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    if (!identifier.isValid()) {
        Result identifierError(Result::InvalidSecretIdentifierError,
                               QLatin1String("The given identifier is invalid"));
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(identifierError)));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("deleteSecret"),
                QVariantList() << QVariant::fromValue<Secret::Identifier>(identifier)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result, LockCodeRequest::LockStatus>
SecretManagerPrivate::queryLockStatus(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, LockCodeRequest::LockStatus>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, LockCodeRequest::LockStatus> reply
            = m_interface->asyncCallWithArgumentList(
                "queryLockStatus",
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::modifyLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("modifyLockCode"),
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::provideLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("provideLockCode"),
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

QDBusPendingReply<Result>
SecretManagerPrivate::forgetLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters,
        SecretManager::UserInteractionMode userInteractionMode)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QString interactionServiceAddress;
    Result uiServiceResult = registerInteractionService(userInteractionMode, &interactionServiceAddress);
    if (uiServiceResult.code() == Result::Failed) {
        return QDBusPendingReply<Result>(
                QDBusMessage().createReply(
                        QVariantList() << QVariant::fromValue<Result>(uiServiceResult)));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("forgetLockCode"),
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters)
                               << QVariant::fromValue<SecretManager::UserInteractionMode>(userInteractionMode)
                               << QVariant::fromValue<QString>(interactionServiceAddress));
    return reply;
}

/*!
  \internal
 */
SecretManagerPrivate *SecretManager::pimpl() const
{
    return d_ptr.data();
}



/*!
  \class SecretManager
  \brief Allows clients to make requests of the system secrets service.
  \inmodule SailfishSecrets
  \inheaderfile Secrets/secretmanager.h

  The SecretManager class provides an interface to the system secrets service.
  In order to perform requests, clients should use the \l Request
  type specific for their needs:

  \list
  \li \l{Sailfish::Secrets::PluginInfoRequest} to request information about available secrets plugins
  \li \l{Sailfish::Secrets::CollectionNamesRequest} to request the names of collections of secrets stored by the secrets service
  \li \l{Sailfish::Secrets::CreateCollectionRequest} to create a collection in which to store secrets
  \li \l{Sailfish::Secrets::DeleteCollectionRequest} to delete a collection of secrets
  \li \l{Sailfish::Secrets::StoreSecretRequest} to store a secret either in a collection or standalone
  \li \l{Sailfish::Secrets::StoredSecretRequest} to retrieve a secret
  \li \l{Sailfish::Secrets::FindSecretsRequest} to search a collection for secrets matching a filter
  \li \l{Sailfish::Secrets::DeleteSecretRequest} to delete a secret
  \li \l{Sailfish::Secrets::InteractionRequest} to request the system mediate a user-interaction flow on behalf of the application
  \endlist
 */


/*!
  \brief Constructs a new SecretManager instance with the given \a parent.
 */
SecretManager::SecretManager(QObject *parent)
    : QObject(parent)
    , d_ptr(new SecretManagerPrivate(this))
{
    if (!d_ptr->m_interface) {
        qCWarning(lcSailfishSecrets) << "Unable to connect to the secrets daemon!  No functionality will be available!";
        return;
    }
}

/*!
  Destroys the SecretManager
 */
SecretManager::~SecretManager()
{
}

/*!
  \brief Returns true if the DBus connection has been established
 */
bool SecretManager::isInitialized() const
{
    Q_D(const SecretManager);
    return d->m_interface;
}

/*!
  \brief Registers the given \a view with the SecretManager.

  The \a view the InteractionView instance which will display any UI required during secret request
  if the authentication plugin for the secret or collection supports \c ApplicationSpecificAuthentication
  in-process UI flows.

  Note that the InteractionView type does not extend QObject and thus no smart pointer (QPointer, etc)
  is used to track the lifetime of the view object.  The client must ensure that the view isn't
  destroyed prior to or during a request performed via the SecretManager, to avoid undefined behaviour.
 */
void SecretManager::registerInteractionView(InteractionView *view)
{
    Q_D(SecretManager);
    // Note: InteractionView is not QObject-derived, so we cannot use QPointer etc.
    d->m_interactionView = view;
}
