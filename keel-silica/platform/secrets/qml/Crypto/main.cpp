// SPDX-FileCopyrightText: 2018-2020 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 - 2020 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "plugintypes.h"
#include "storedkeyidentifiersrequestwrapper.h"

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

void Sailfish::Crypto::Plugin::CryptoPlugin::initializeEngine(QQmlEngine *, const char *)
{
}

void Sailfish::Crypto::Plugin::CryptoPlugin::registerTypes(const char *uri)
{
    qRegisterMetaType<Sailfish::Crypto::Result>("Sailfish::Crypto::Result");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Crypto::Result>();
#endif
    keelRegisterGadget<Sailfish::Crypto::Result>(uri, "Result", QStringLiteral("Result objects cannot be constructed directly in QML"));

    qRegisterMetaType<Sailfish::Crypto::Key>("Sailfish::Crypto::Key");
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0) // Modified by Shipwright for Qt 6: comparators are automatic
    QMetaType::registerComparators<Sailfish::Crypto::Key>();
#endif
    keelRegisterGadget<Sailfish::Crypto::Key>(uri, "Key", QStringLiteral("Key objects cannot be constructed directly in QML"));

    qmlRegisterUncreatableType<Sailfish::Crypto::Request>(uri, 1, 0, "Request", QStringLiteral("Request is an abstract class, can't construct in QML"));
    qRegisterMetaType<Sailfish::Crypto::Request::Status>("Sailfish::Crypto::Request::Status");
    keelRegisterGadget<Sailfish::Crypto::PluginInfo>(uri, "PluginInfo", QStringLiteral("PluginInfo objects cannot be constructed directly in QML"));
    qmlRegisterType<Sailfish::Crypto::Plugin::PluginInfoRequestWrapper>(uri, 1, 0, "PluginInfoRequest");
    qmlRegisterType<Sailfish::Crypto::SeedRandomDataGeneratorRequest>(uri, 1, 0, "SeedRandomDataGeneratorRequest");
    qmlRegisterType<Sailfish::Crypto::GenerateRandomDataRequest>(uri, 1, 0, "GenerateRandomDataRequest");
    qmlRegisterType<Sailfish::Crypto::GenerateKeyRequest>(uri, 1, 0, "GenerateKeyRequest");
    qmlRegisterType<Sailfish::Crypto::GenerateStoredKeyRequest>(uri, 1, 0, "GenerateStoredKeyRequest");
    qmlRegisterType<Sailfish::Crypto::ImportKeyRequest>(uri, 1, 0, "ImportKeyRequest");
    qmlRegisterType<Sailfish::Crypto::ImportStoredKeyRequest>(uri, 1, 0, "ImportStoredKeyRequest");
    qmlRegisterType<Sailfish::Crypto::StoredKeyRequest>(uri, 1, 0, "StoredKeyRequest");
    qmlRegisterType<Sailfish::Crypto::Plugin::StoredKeyIdentifiersRequestWrapper>(uri, 1, 0, "StoredKeyIdentifiersRequest");
    qmlRegisterType<Sailfish::Crypto::DeleteStoredKeyRequest>(uri, 1, 0, "DeleteStoredKeyRequest");
    qmlRegisterType<Sailfish::Crypto::EncryptRequest>(uri, 1, 0, "EncryptRequest");
    qmlRegisterType<Sailfish::Crypto::DecryptRequest>(uri, 1, 0, "DecryptRequest");
    qmlRegisterType<Sailfish::Crypto::CalculateDigestRequest>(uri, 1, 0, "CalculateDigestRequest");
    qmlRegisterType<Sailfish::Crypto::SignRequest>(uri, 1, 0, "SignRequest");
    qmlRegisterType<Sailfish::Crypto::VerifyRequest>(uri, 1, 0, "VerifyRequest");
    qmlRegisterType<Sailfish::Crypto::CipherRequest>(uri, 1, 0, "CipherRequest");

    keelRegisterGadget<Sailfish::Crypto::KeyDerivationParameters>(uri, "KeyDerivationParameters", QStringLiteral("Use CryptoManager.constructPbkdfParams, can't construct Q_GADGET type KeyDerivationParameters in QML"));

    keelRegisterGadget<Sailfish::Crypto::KeyPairGenerationParameters>(uri, "KeyPairGenerationParameters", QStringLiteral("Use CryptoManager.constructRsaKeygenParams, can't construct Q_GADGET type KeyPairGenerationParameters in QML"));
    keelRegisterGadget<Sailfish::Crypto::EcKeyPairGenerationParameters>(uri, "EcKeyPairGenerationParameters", QStringLiteral("Use CryptoManager.constructRsaKeygenParams, can't construct Q_GADGET type EcKeyPairGenerationParameters in QML"));
    keelRegisterGadget<Sailfish::Crypto::RsaKeyPairGenerationParameters>(uri, "RsaKeyPairGenerationParameters", QStringLiteral("Use CryptoManager.constructRsaKeygenParams, can't construct Q_GADGET type RsaKeyPairGenerationParameters in QML"));
    keelRegisterGadget<Sailfish::Crypto::DsaKeyPairGenerationParameters>(uri, "DsaKeyPairGenerationParameters", QStringLiteral("Use CryptoManager.constructRsaKeygenParams, can't construct Q_GADGET type DsaKeyPairGenerationParameters in QML"));
    keelRegisterGadget<Sailfish::Crypto::DhKeyPairGenerationParameters>(uri, "DhKeyPairGenerationParameters", QStringLiteral("Use CryptoManager.constructRsaKeygenParams, can't construct Q_GADGET type DhKeyPairGenerationParameters in QML"));

    keelRegisterGadget<Sailfish::Crypto::InteractionParameters>(uri, "InteractionParameters", QStringLiteral("Can't construct InteractionParameters in QML"));
    keelRegisterGadget<Sailfish::Crypto::InteractionParameters::PromptText>(uri, "PromptText", QStringLiteral("Can't construct PromptText in QML"));

    qmlRegisterType<Sailfish::Crypto::Plugin::CryptoManager>(uri, 1, 0, "CryptoManager");
}

/*!
  \qmltype CryptoManager
  \brief Allows clients to make requests of the system crypto service.
  \inqmlmodule Sailfish.Crypto
  \instantiates Sailfish::Crypto::CryptoManager
*/

/*!
  \qmlproperty string CryptoManager::defaultCryptoPluginName
*/

/*!
  \qmlproperty string CryptoManager::defaultCryptoStoragePluginName
*/

Sailfish::Crypto::Plugin::CryptoManager::CryptoManager(QObject *parent)
    : Sailfish::Crypto::CryptoManager(parent)
{
}

Sailfish::Crypto::Plugin::CryptoManager::~CryptoManager()
{
}

/*!
  \qmlmethod Result CryptoManager::constructResult()
*/

Sailfish::Crypto::Result Sailfish::Crypto::Plugin::CryptoManager::constructResult() const
{
    return Sailfish::Crypto::Result();
}

/*!
  \qmlmethod Key CryptoManager::constructKey()
*/
Sailfish::Crypto::Key Sailfish::Crypto::Plugin::CryptoManager::constructKey() const
{
    return Sailfish::Crypto::Key();
}

/*!
  \qmlmethod Key CryptoManager::constructKey(string name, string collectionName, string storagePluginName)
*/
Sailfish::Crypto::Key Sailfish::Crypto::Plugin::CryptoManager::constructKey(const QString &name, const QString &collectionName, const QString &storagePluginName) const
{
    return Sailfish::Crypto::Key(name, collectionName, storagePluginName);
}

/*!
  \qmlmethod Key CryptoManager::constructKeyTemplate(Algorithm algorithm, Operations operations, Key.Origin origin)
*/
Sailfish::Crypto::Key Sailfish::Crypto::Plugin::CryptoManager::constructKeyTemplate(
            Sailfish::Crypto::CryptoManager::Algorithm algorithm,
            Sailfish::Crypto::CryptoManager::Operations operations,
            Sailfish::Crypto::Key::Origin origin) const
{
    Sailfish::Crypto::Key keyTemplate;
    keyTemplate.setAlgorithm(algorithm);
    keyTemplate.setOperations(operations);
    keyTemplate.setOrigin(origin);
    return keyTemplate;
}

/*!
  \qmlmethod Key.Identifier CryptoManager::constructIdentifier(string name, string collectionName, string storagePluginName)
*/
  
Sailfish::Crypto::Key::Identifier Sailfish::Crypto::Plugin::CryptoManager::constructIdentifier(const QString &name, const QString &collectionName, const QString &storagePluginName) const
{
    return Sailfish::Crypto::Key::Identifier(name, collectionName, storagePluginName);
}

/*!
  \qmlmethod KeyDerivationParameters CryptoManager::constructPbkdf2Params(ArrayBuffer data, ArrayBuffer salt, int iterations, int outputKeySize)
*/

QVariant Sailfish::Crypto::Plugin::CryptoManager::constructPbkdf2Params(const QByteArray &data, const QByteArray &salt, int iterations, int outputKeySize) const
{
    Sailfish::Crypto::KeyDerivationParameters kdfParams;
    kdfParams.setKeyDerivationFunction(Sailfish::Crypto::CryptoManager::KdfPkcs5Pbkdf2);
    kdfParams.setKeyDerivationMac(Sailfish::Crypto::CryptoManager::MacHmac);
    kdfParams.setKeyDerivationDigestFunction(Sailfish::Crypto::CryptoManager::DigestSha512);
    kdfParams.setIterations(iterations);
    kdfParams.setOutputKeySize(outputKeySize);
    kdfParams.setSalt(salt);
    kdfParams.setInputData(data);
    return QVariant::fromValue<KeyDerivationParameters>(kdfParams);
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructRsaKeygenParams()
*/

QVariant Sailfish::Crypto::Plugin::CryptoManager::constructRsaKeygenParams() const
{
    return QVariant::fromValue<KeyPairGenerationParameters>(RsaKeyPairGenerationParameters());
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructRsaKeygenParams(object args)
*/

QVariant Sailfish::Crypto::Plugin::CryptoManager::constructRsaKeygenParams(const QVariantMap &args) const
{
    QVariantMap customParams;
    RsaKeyPairGenerationParameters params;
    for (QVariantMap::ConstIterator it = args.constBegin(); it != args.constEnd(); it++) {
        if (it.key().compare("modulusLength") == 0) {
            params.setModulusLength(it->toInt());
        } else if (it.key().compare("numberPrimes") == 0) {
            params.setNumberPrimes(it->toInt());
        } else if (it.key().compare("publicExponent") == 0) {
            params.setPublicExponent(it->value<quint64>());
        } else {
            customParams.insert(it.key(), it.value());
        }
    }
    params.setCustomParameters(customParams);
    return QVariant::fromValue<KeyPairGenerationParameters>(params);
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructEcKeygenParams()
*/

QVariant Sailfish::Crypto::Plugin::CryptoManager::constructEcKeygenParams() const
{
    return QVariant::fromValue<KeyPairGenerationParameters>(EcKeyPairGenerationParameters());
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructEcKeygenParams(args)
*/
QVariant Sailfish::Crypto::Plugin::CryptoManager::constructEcKeygenParams(const QVariantMap &args) const
{
    EcKeyPairGenerationParameters params;
    params.setCustomParameters(args);
    return QVariant::fromValue<KeyPairGenerationParameters>(params);
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructDsaKeygenParams()
*/
QVariant Sailfish::Crypto::Plugin::CryptoManager::constructDsaKeygenParams() const
{
    return QVariant::fromValue<KeyPairGenerationParameters>(DsaKeyPairGenerationParameters());
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructDsaKeygenParams(args)
*/
QVariant Sailfish::Crypto::Plugin::CryptoManager::constructDsaKeygenParams(const QVariantMap &args) const
{
    QVariantMap customParams;
    DsaKeyPairGenerationParameters params;
    for (QVariantMap::ConstIterator it = args.constBegin(); it != args.constEnd(); it++) {
        if (it.key().compare("modulusLength") == 0) {
            params.setModulusLength(it->toInt());
        } else if (it.key().compare("primeFactorLength") == 0) {
            params.setPrimeFactorLength(it->toInt());
        } else if (it.key().compare("base") == 0) {
            params.setBase(it->toByteArray());
        } else if (it.key().compare("modulus") == 0) {
            params.setModulus(it->toByteArray());
        } else if (it.key().compare("generateFamilyParameters") == 0) {
            params.setGenerateFamilyParameters(it->toBool());
        } else if (it.key().compare("primeFactor") == 0) {
            params.setPrimeFactor(it->toByteArray());
        } else {
            customParams.insert(it.key(), it.value());
        }
    }
    params.setCustomParameters(customParams);
    return QVariant::fromValue<KeyPairGenerationParameters>(params);
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructDhKeygenParams()
*/
QVariant Sailfish::Crypto::Plugin::CryptoManager::constructDhKeygenParams() const
{
    return QVariant::fromValue<KeyPairGenerationParameters>(DhKeyPairGenerationParameters());
}

/*!
  \qmlmethod KeyPairGenerationParameters CryptoManager::constructDhKeygenParams(args)
*/
QVariant Sailfish::Crypto::Plugin::CryptoManager::constructDhKeygenParams(const QVariantMap &args) const
{
    QVariantMap customParams;
    DhKeyPairGenerationParameters params;
    for (QVariantMap::ConstIterator it = args.constBegin(); it != args.constEnd(); it++) {
        if (it.key().compare("modulusLength") == 0) {
            params.setModulusLength(it->toInt());
        } else if (it.key().compare("privateExponentLength") == 0) {
            params.setPrivateExponentLength(it->toInt());
        } else if (it.key().compare("base") == 0) {
            params.setBase(it->toByteArray());
        } else if (it.key().compare("modulus") == 0) {
            params.setModulus(it->toByteArray());
        } else if (it.key().compare("generateFamilyParameters") == 0) {
            params.setGenerateFamilyParameters(it->toBool());
        } else {
            customParams.insert(it.key(), it.value());
        }
    }
    params.setCustomParameters(customParams);
    return QVariant::fromValue<KeyPairGenerationParameters>(params);
}

/*!
  \qmlmethod string CryptoManager::toBase64(ArrayBuffer data)
*/
QString Sailfish::Crypto::Plugin::CryptoManager::toBase64(const QByteArray &data) const
{
    return QString::fromUtf8(data.toBase64(QByteArray::KeepTrailingEquals | QByteArray::Base64UrlEncoding));
}

/*!
  \qmlmethod ArrayBuffer CryptoManager::fromBase64(string b64)
*/
QByteArray Sailfish::Crypto::Plugin::CryptoManager::fromBase64(const QString &b64) const
{
    return b64.toUtf8().fromBase64(b64.toUtf8(), QByteArray::KeepTrailingEquals | QByteArray::Base64UrlEncoding);
}

/*!
  \qmlmethod string CryptoManager::stringFromBytes(ArrayBuffer stringData)
*/
QString Sailfish::Crypto::Plugin::CryptoManager::stringFromBytes(const QByteArray &stringData) const
{
    return QString::fromUtf8(stringData);
}
