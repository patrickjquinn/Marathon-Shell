// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRETMANAGER_P_H
#define LIBSAILFISHSECRETS_SECRETMANAGER_P_H

#include "Secrets/secretmanager.h"
#include "Secrets/secret.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/secretsdaemonconnection_p.h"
#include "Secrets/plugininfo.h"
#include "Secrets/healthcheckrequest.h"
#include "Secrets/interactionview.h"
#include "Secrets/interactionservice_p.h"
#include "Secrets/lockcoderequest.h"

#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusContext>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusMetaType>
#include <QtDBus/QDBusArgument>

#include <QtCore/QObject>
#include <QtCore/QPointer>

namespace Sailfish {

namespace Secrets {

class SecretManager;

// not actually part of the public API, but exporting symbols for unit tests.
class SAILFISH_SECRETS_API SecretManagerPrivate : public QObject
{
    Q_OBJECT

public:
    SecretManagerPrivate(SecretManager *parent = Q_NULLPTR);
    ~SecretManagerPrivate();

    // ui communication happens via a peer-to-peer dbus connection in which the sailfishsecretsd process becomes the client.
    void handleUiConnection(const QDBusConnection &connection);

    // register the ui service if required, and return it's address.
    Sailfish::Secrets::Result registerInteractionService(Sailfish::Secrets::SecretManager::UserInteractionMode mode, QString *address);

    // retrieve information about plugins
    QDBusPendingReply<Sailfish::Secrets::Result,
                      QVector<Sailfish::Secrets::PluginInfo>,
                      QVector<Sailfish::Secrets::PluginInfo>,
                      QVector<Sailfish::Secrets::PluginInfo>,
                      QVector<Sailfish::Secrets::PluginInfo> > getPluginInfo();

    // retrieve information about health
    QDBusPendingReply<Sailfish::Secrets::Result,
                      HealthCheckRequest::Health,
                      HealthCheckRequest::Health> getHealthInfo();

    // retrieve user input data
    QDBusPendingReply<Sailfish::Secrets::Result, QByteArray> userInput(
            const Sailfish::Secrets::InteractionParameters &uiParams);

    // retrieve the names of collections (map<name,isLocked>)
    QDBusPendingReply<Sailfish::Secrets::Result, QMap<QString, bool> > collectionNames(
            const QString &storagePluginName);

    // create a DeviceLock-protected collection
    QDBusPendingReply<Sailfish::Secrets::Result> createCollection(
            const QString &collectionName,
            const QString &storagePluginName,
            const QString &encryptionPluginName,
            Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic unlockSemantic,
            Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode);

    // create a CustomLock-protected collection
    QDBusPendingReply<Sailfish::Secrets::Result> createCollection(
            const QString &collectionName,
            const QString &storagePluginName,
            const QString &encryptionPluginName,
            const QString &authenticationPluginName,
            Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic unlockSemantic,
            Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // delete a collection
    QDBusPendingReply<Sailfish::Secrets::Result> deleteCollection(
            const QString &collectionName,
            const QString &storagePluginName,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // set a secret in a collection.  Will immediately fail if the secret's identifier is standalone.
    QDBusPendingReply<Sailfish::Secrets::Result> setSecret(
            const Sailfish::Secrets::Secret &secret,
            const Sailfish::Secrets::InteractionParameters &uiParams,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // set a standalone DeviceLock-protected secret
    QDBusPendingReply<Sailfish::Secrets::Result> setSecret(
            const Sailfish::Secrets::Secret &secret,
            const QString &encryptionPluginName,
            const Sailfish::Secrets::InteractionParameters &uiParams,
            Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic unlockSemantic,
            Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // set a standalone CustomLock-protected secret
    QDBusPendingReply<Sailfish::Secrets::Result> setSecret(
            const Sailfish::Secrets::Secret &secret,
            const QString &encryptionPluginName,
            const QString &authenticationPluginName,
            const Sailfish::Secrets::InteractionParameters &uiParams,
            Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic unlockSemantic,
            Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // get a secret (either from a collection or standalone, depending on the identifier)
    QDBusPendingReply<Sailfish::Secrets::Result, Sailfish::Secrets::Secret> getSecret(
            const Sailfish::Secrets::Secret::Identifier &identifier,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // find secrets from a collection via filter
    QDBusPendingReply<Sailfish::Secrets::Result, QVector<Sailfish::Secrets::Secret::Identifier> > findSecrets(
            const QString &collectionName,
            const QString &storagePluginName,
            const Sailfish::Secrets::Secret::FilterData &filter,
            Sailfish::Secrets::SecretManager::FilterOperator filterOperator,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // find standalone secrets via filter
    QDBusPendingReply<Sailfish::Secrets::Result, QVector<Sailfish::Secrets::Secret::Identifier> > findSecrets(
            const QString &storagePluginName,
            const Sailfish::Secrets::Secret::FilterData &filter,
            Sailfish::Secrets::SecretManager::FilterOperator filterOperator,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // delete a secret (either from a collection or standalone, depending on the identifier)
    QDBusPendingReply<Sailfish::Secrets::Result> deleteSecret(
            const Sailfish::Secrets::Secret::Identifier &identifier,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // query the lock status of a plugin or the metadata db
    QDBusPendingReply<Sailfish::Secrets::Result, Sailfish::Secrets::LockCodeRequest::LockStatus> queryLockStatus(
            Sailfish::Secrets::LockCodeRequest::LockCodeTargetType lockCodeTargetType,
            const QString &lockCodeTarget);

    // modify the passphrase used to lock/unlock a plugin or the metadata db
    QDBusPendingReply<Sailfish::Secrets::Result> modifyLockCode(
            Sailfish::Secrets::LockCodeRequest::LockCodeTargetType lockCodeTargetType,
            const QString &lockCodeTarget,
            const Sailfish::Secrets::InteractionParameters &interactionParameters,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // provide the passphrase to lock/unlock a plugin or the metadata db
    QDBusPendingReply<Sailfish::Secrets::Result> provideLockCode(
            Sailfish::Secrets::LockCodeRequest::LockCodeTargetType lockCodeTargetType,
            const QString &lockCodeTarget,
            const Sailfish::Secrets::InteractionParameters &interactionParameters,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

    // forget the passphrase and relock a plugin or the metadata db
    QDBusPendingReply<Sailfish::Secrets::Result> forgetLockCode(
            Sailfish::Secrets::LockCodeRequest::LockCodeTargetType lockCodeTargetType,
            const QString &lockCodeTarget,
            const Sailfish::Secrets::InteractionParameters &interactionParameters,
            Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode);

private:
    friend class SecretManager;
    friend class InteractionService;
    InteractionService *m_uiService;
    InteractionView *m_interactionView;
    QPointer<Sailfish::Secrets::SecretsDaemonConnection> m_secrets;
    QDBusInterface *m_interface;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_SECRETMANAGER_P_H
