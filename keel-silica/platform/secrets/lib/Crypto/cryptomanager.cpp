// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"
#include "Crypto/key.h"
#include "Crypto/keypairgenerationparameters.h"
#include "Crypto/keyderivationparameters.h"
#include "Crypto/interactionparameters.h"
#include "Crypto/plugininfo.h"
#include "Crypto/lockcoderequest.h"

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

Q_LOGGING_CATEGORY(lcSailfishCrypto, "org.sailfishos.crypto", QtWarningMsg)

using namespace Sailfish::Crypto;

const QString CryptoManager::DefaultCryptoPluginName = QStringLiteral("plugin.crypto.default");
const QString CryptoManager::DefaultCryptoStoragePluginName = QStringLiteral("plugin.cryptostorage.default");

/*!
  \internal
  \class CryptoManagerPrivate
  \brief Performs P2P DBus calls to the system crypto service
  \inmodule SailfishCrypto
 */

/*!
  \internal
 */
CryptoManagerPrivate::CryptoManagerPrivate(CryptoManager *parent)
    : m_crypto(CryptoDaemonConnection::instance())
    , m_interface(m_crypto->connect()
                  ? m_crypto->createInterface(QLatin1String("/Sailfish/Crypto"), QLatin1String("org.sailfishos.crypto"), parent)
                  : Q_NULLPTR)
{
}

/*!
  \internal
 */
CryptoManagerPrivate::~CryptoManagerPrivate()
{
    CryptoDaemonConnection::releaseInstance();
    m_interface = Q_NULLPTR;
}

/*!
  \internal
  \brief Returns the names of available crypto plugins as well as the names of available (Secrets) storage plugins

  Any plugin which is both a crypto plugin and a storage plugin must be
  able to implement stored-key functionality (e.g. GenerateStoredKeyRequest).
 */
QDBusPendingReply<Result, QVector<PluginInfo>, QVector<PluginInfo> >
CryptoManagerPrivate::getPluginInfo()
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QVector<PluginInfo>, QVector<PluginInfo> >(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QVector<PluginInfo>, QVector<PluginInfo> > reply
            = m_interface->asyncCall("getPluginInfo");

    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result, QByteArray>
CryptoManagerPrivate::generateRandomData(
        quint64 numberBytes,
        const QString &csprngEngineName,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("generateRandomData"),
                QVariantList() << QVariant::fromValue<quint64>(numberBytes)
                               << QVariant::fromValue<QString>(csprngEngineName)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result>
CryptoManagerPrivate::seedRandomDataGenerator(
        const QByteArray &seedData,
        double entropyEstimate,
        const QString &csprngEngineName,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("seedRandomDataGenerator"),
                QVariantList() << QVariant::fromValue<QByteArray>(seedData)
                               << QVariant::fromValue<double>(entropyEstimate)
                               << QVariant::fromValue<QString>(csprngEngineName)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result, QByteArray>
CryptoManagerPrivate::generateInitializationVector(
        Sailfish::Crypto::CryptoManager::Algorithm algorithm,
        Sailfish::Crypto::CryptoManager::BlockMode blockMode,
        int keySize,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("generateInitializationVector"),
                QVariantList() << QVariant::fromValue<CryptoManager::Algorithm>(algorithm)
                               << QVariant::fromValue<CryptoManager::BlockMode>(blockMode)
                               << QVariant::fromValue<int>(keySize)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, Key>
CryptoManagerPrivate::generateKey(
        const Key &keyTemplate,
        const KeyPairGenerationParameters &kpgParams,
        const KeyDerivationParameters &skdfParams,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Key>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Key> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("generateKey"),
                QVariantList() << QVariant::fromValue<Key>(keyTemplate)
                               << QVariant::fromValue<KeyPairGenerationParameters>(kpgParams)
                               << QVariant::fromValue<KeyDerivationParameters>(skdfParams)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, Key>
CryptoManagerPrivate::generateStoredKey(
        const Key &keyTemplate,
        const KeyPairGenerationParameters &kpgParams,
        const KeyDerivationParameters &skdfParams,
        const InteractionParameters &uiParams,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Key>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Key> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("generateStoredKey"),
                QVariantList() << QVariant::fromValue<Key>(keyTemplate)
                               << QVariant::fromValue<KeyPairGenerationParameters>(kpgParams)
                               << QVariant::fromValue<KeyDerivationParameters>(skdfParams)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, Key>
CryptoManagerPrivate::importKey(
        const QByteArray &data,
        const InteractionParameters &uiParams,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Key>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Key> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("importKey"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, Key>
CryptoManagerPrivate::importStoredKey(
        const QByteArray &data,
        const Key &keyTemplate,
        const InteractionParameters &uiParams,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Key>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Key> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("importStoredKey"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<Key>(keyTemplate)
                               << QVariant::fromValue<InteractionParameters>(uiParams)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, Key>
CryptoManagerPrivate::storedKey(
        const Key::Identifier &identifier,
        Key::Components keyComponents,
        const QVariantMap &customParameters)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Key>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Key> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("storedKey"),
                QVariantList() << QVariant::fromValue<Key::Identifier>(identifier)
                               << QVariant::fromValue<Key::Components>(keyComponents)
                               << QVariant::fromValue<QVariantMap>(customParameters));
    return reply;
}

QDBusPendingReply<Result>
CryptoManagerPrivate::deleteStoredKey(
        const Key::Identifier &identifier)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("deleteStoredKey"),
                QVariantList() << QVariant::fromValue<Key::Identifier>(identifier));
    return reply;
}

QDBusPendingReply<Result, QVector<Key::Identifier> >
CryptoManagerPrivate::storedKeyIdentifiers(
        const QString &storagePluginName,
        const QString &collectionName,
        const QVariantMap &customParameters)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QVector<Key::Identifier> >(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QVector<Key::Identifier> > reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("storedKeyIdentifiers"),
                QVariantList() << QVariant::fromValue<QString>(storagePluginName)
                               << QVariant::fromValue<QString>(collectionName)
                               << QVariant::fromValue<QVariantMap>(customParameters));
    return reply;
}

QDBusPendingReply<Result, QByteArray>
CryptoManagerPrivate::calculateDigest(
        const QByteArray &data,
        CryptoManager::SignaturePadding padding,
        CryptoManager::DigestFunction digestFunction,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("calculateDigest"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<CryptoManager::SignaturePadding>(padding)
                               << QVariant::fromValue<CryptoManager::DigestFunction>(digestFunction)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, QByteArray>
CryptoManagerPrivate::sign(
        const QByteArray &data,
        const Key &key,
        CryptoManager::SignaturePadding padding,
        CryptoManager::DigestFunction digestFunction,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("sign"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<Key>(key)
                               << QVariant::fromValue<CryptoManager::SignaturePadding>(padding)
                               << QVariant::fromValue<CryptoManager::DigestFunction>(digestFunction)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, CryptoManager::VerificationStatus> CryptoManagerPrivate::verify(
        const QByteArray &signature,
        const QByteArray &data,
        const Key &key,
        CryptoManager::SignaturePadding padding,
        CryptoManager::DigestFunction digestFunction,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, Sailfish::Crypto::CryptoManager::VerificationStatus>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, Sailfish::Crypto::CryptoManager::VerificationStatus> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("verify"),
                QVariantList() << QVariant::fromValue<QByteArray>(signature)
                               << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<Key>(key)
                               << QVariant::fromValue<CryptoManager::SignaturePadding>(padding)
                               << QVariant::fromValue<CryptoManager::DigestFunction>(digestFunction)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, QByteArray, QByteArray>
CryptoManagerPrivate::encrypt(
        const QByteArray &data,
        const QByteArray &iv,
        const Key &key, // or keyreference, i.e. Key(keyName)
        CryptoManager::BlockMode blockMode,
        CryptoManager::EncryptionPadding padding,
        const QByteArray &authenticationData,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("encrypt"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<QByteArray>(iv)
                               << QVariant::fromValue<Key>(key)
                               << QVariant::fromValue<CryptoManager::BlockMode>(blockMode)
                               << QVariant::fromValue<CryptoManager::EncryptionPadding>(padding)
                               << QVariant::fromValue<QByteArray>(authenticationData)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus> CryptoManagerPrivate::decrypt(
        const QByteArray &data,
        const QByteArray &iv,
        const Key &key, // or keyreference, i.e. Key(keyName)
        CryptoManager::BlockMode blockMode,
        CryptoManager::EncryptionPadding padding,
        const QByteArray &authenticationData,
        const QByteArray &authenticationTag,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus> reply
            = m_interface->asyncCallWithArgumentList(
                QStringLiteral("decrypt"),
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<QByteArray>(iv)
                               << QVariant::fromValue<Key>(key)
                               << QVariant::fromValue<CryptoManager::BlockMode>(blockMode)
                               << QVariant::fromValue<CryptoManager::EncryptionPadding>(padding)
                               << QVariant::fromValue<QByteArray>(authenticationData)
                               << QVariant::fromValue<QByteArray>(authenticationTag)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result, quint32>
CryptoManagerPrivate::initializeCipherSession(
        const QByteArray &initializationVector,
        const Sailfish::Crypto::Key &key, // or keyreference
        const Sailfish::Crypto::CryptoManager::Operation operation,
        const Sailfish::Crypto::CryptoManager::BlockMode blockMode,
        const Sailfish::Crypto::CryptoManager::EncryptionPadding encryptionPadding,
        const Sailfish::Crypto::CryptoManager::SignaturePadding signaturePadding,
        const Sailfish::Crypto::CryptoManager::DigestFunction digest,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, quint32>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, quint32> reply
            = m_interface->asyncCallWithArgumentList(
                "initializeCipherSession",
                QVariantList() << QVariant::fromValue<QByteArray>(initializationVector)
                               << QVariant::fromValue<Key>(key)
                               << QVariant::fromValue<CryptoManager::Operation>(operation)
                               << QVariant::fromValue<CryptoManager::BlockMode>(blockMode)
                               << QVariant::fromValue<CryptoManager::EncryptionPadding>(encryptionPadding)
                               << QVariant::fromValue<CryptoManager::SignaturePadding>(signaturePadding)
                               << QVariant::fromValue<CryptoManager::DigestFunction>(digest)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result>
CryptoManagerPrivate::updateCipherSessionAuthentication(
        const QByteArray &authenticationData,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName,
        quint32 cipherSessionToken)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                "updateCipherSessionAuthentication",
                QVariantList() << QVariant::fromValue<QByteArray>(authenticationData)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName)
                               << QVariant::fromValue<quint32>(cipherSessionToken));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result, QByteArray>
CryptoManagerPrivate::updateCipherSession(
        const QByteArray &data,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName,
        quint32 cipherSessionToken)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray> reply
            = m_interface->asyncCallWithArgumentList(
                "updateCipherSession",
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName)
                               << QVariant::fromValue<quint32>(cipherSessionToken));
    return reply;
}

QDBusPendingReply<Sailfish::Crypto::Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus>
CryptoManagerPrivate::finalizeCipherSession(
        const QByteArray &data,
        const QVariantMap &customParameters,
        const QString &cryptosystemProviderName,
        quint32 cipherSessionToken)
{
    if (!m_interface) {
        return QDBusPendingReply<Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result, QByteArray, Sailfish::Crypto::CryptoManager::VerificationStatus> reply
            = m_interface->asyncCallWithArgumentList(
                "finalizeCipherSession",
                QVariantList() << QVariant::fromValue<QByteArray>(data)
                               << QVariant::fromValue<QVariantMap>(customParameters)
                               << QVariant::fromValue<QString>(cryptosystemProviderName)
                               << QVariant::fromValue<quint32>(cipherSessionToken));
    return reply;
}

QDBusPendingReply<Result, LockCodeRequest::LockStatus>
CryptoManagerPrivate::queryLockStatus(
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
CryptoManagerPrivate::modifyLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                "modifyLockCode",
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters));
    return reply;
}

QDBusPendingReply<Result>
CryptoManagerPrivate::provideLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                "provideLockCode",
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters));
    return reply;
}

QDBusPendingReply<Result>
CryptoManagerPrivate::forgetLockCode(
        LockCodeRequest::LockCodeTargetType lockCodeTargetType,
        const QString &lockCodeTarget,
        const InteractionParameters &interactionParameters)
{
    if (!m_interface) {
        return QDBusPendingReply<Result>(
                    QDBusMessage::createError(QDBusError::Other,
                                              QStringLiteral("Not connected to daemon")));
    }

    QDBusPendingReply<Result> reply
            = m_interface->asyncCallWithArgumentList(
                "forgetLockCode",
                QVariantList() << QVariant::fromValue<LockCodeRequest::LockCodeTargetType>(lockCodeTargetType)
                               << QVariant::fromValue<QString>(lockCodeTarget)
                               << QVariant::fromValue<InteractionParameters>(interactionParameters));
    return reply;
}

/*!
  \internal
 */
CryptoManagerPrivate *CryptoManager::pimpl() const
{
    return d_ptr.data();
}

/*!
  \class CryptoManager
  \brief Allows clients to make requests of the system crypto service.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/cryptomanager.h

  The CryptoManager class provides an interface to the system crypto service.
  In order to perform requests, clients should use the \l Request
  type specific for their needs:

  \list
  \li \l{PluginInfoRequest} to retrieve information about available crypto plugins
  \li \l{LockCodeRequest} to set the lock code for, lock, or unlock a crypto plugin
  \li \l{SeedRandomDataGeneratorRequest} to seed a crypto plugin's random number generator
  \li \l{GenerateRandomDataRequest} to generate random data
  \li \l{GenerateKeyRequest} to generate a \l{Key}
  \li \l{GenerateStoredKeyRequest} to generate a securely-stored \l{Key}
  \li \l{ImportKeyRequest} to import a \l{Key} from a data file
  \li \l{ImportStoredKeyRequest} to import a \l{Key} from a data file and store it securely
  \li \l{StoredKeyRequest} to retrieve a securely-stored \l{Key}
  \li \l{StoredKeyIdentifiersRequest} to retrieve the identifiers of securely-stored \l{Key}{Keys}
  \li \l{DeleteStoredKeyRequest} to delete a securely-stored \l{Key}
  \li \l{EncryptRequest} to encrypt data with a given \l{Key}
  \li \l{DecryptRequest} to decrypt data with a given \l{Key}
  \li \l{CalculateDigestRequest} to calculate a digest (non-keyed hash) of some data
  \li \l{SignRequest} to generate a signature for some data with a given \l{Key}
  \li \l{VerifyRequest} to verify if a signature was generated with a given \l{Key}
  \li \l{CipherRequest} to start a cipher session with which to encrypt, decrypt, sign or verify a stream of data
  \endlist
 */

/*!
  \brief Constructs a new CryptoManager instance with the given \a parent.
 */
CryptoManager::CryptoManager(QObject *parent)
    : QObject(parent)
    , d_ptr(new CryptoManagerPrivate(this))
{
    if (!d_ptr->m_interface) {
        qCWarning(lcSailfishCrypto) << "Unable to connect to the crypto daemon!  No functionality will be available!";
        return;
    }
}

/*!
  \brief Destroys the CryptoManager.
 */
CryptoManager::~CryptoManager()
{
}

/*!
  \brief Returns true if the manager is initialized and can be used to perform requests.
 */
bool CryptoManager::isInitialized() const
{
    Q_D(const CryptoManager);
    return d->m_interface;
}
