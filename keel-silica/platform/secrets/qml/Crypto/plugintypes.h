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

#ifndef SAILFISHCRYPTO_QML_PLUGINTYPES_H
#define SAILFISHCRYPTO_QML_PLUGINTYPES_H

#include "Crypto/result.h"
#include "Crypto/key.h"
#include "Crypto/cryptomanager.h"

#include "Crypto/plugininforequest.h"
#include "Crypto/seedrandomdatageneratorrequest.h"
#include "Crypto/generaterandomdatarequest.h"
#include "Crypto/generatekeyrequest.h"
#include "Crypto/generatestoredkeyrequest.h"
#include "Crypto/importkeyrequest.h"
#include "Crypto/importstoredkeyrequest.h"
#include "Crypto/storedkeyrequest.h"
#include "Crypto/deletestoredkeyrequest.h"
#include "Crypto/storedkeyidentifiersrequest.h"
#include "Crypto/encryptrequest.h"
#include "Crypto/decryptrequest.h"
#include "Crypto/calculatedigestrequest.h"
#include "Crypto/signrequest.h"
#include "Crypto/verifyrequest.h"
#include "Crypto/cipherrequest.h"

#include <QQmlExtensionPlugin>
#include <QQmlParserStatus>
#include <QQmlEngine>

namespace Sailfish {

namespace Crypto {

namespace Plugin {

class CryptoPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "Sailfish.Crypto")

public:
    void initializeEngine(QQmlEngine *, const char *);
    virtual void registerTypes(const char *uri);
};

class CryptoManager : public Sailfish::Crypto::CryptoManager
{
    Q_OBJECT
    Q_PROPERTY(QString defaultCryptoPluginName READ defaultCryptoPluginName CONSTANT)
    Q_PROPERTY(QString defaultCryptoStoragePluginName READ defaultCryptoStoragePluginName CONSTANT)

public:
    CryptoManager(QObject *parent = Q_NULLPTR);
    virtual ~CryptoManager() Q_DECL_OVERRIDE;

    // QML API - make static members accessible
    QString defaultCryptoPluginName() const { return DefaultCryptoPluginName; }
    QString defaultCryptoStoragePluginName() const { return DefaultCryptoStoragePluginName; }

    // QML API - allow clients to construct "uncreatable" value types
    Q_INVOKABLE Sailfish::Crypto::Result constructResult() const;
    Q_INVOKABLE Sailfish::Crypto::Key constructKey() const;
    Q_INVOKABLE Sailfish::Crypto::Key constructKey(const QString &name,
                                 const QString &collectionName,
                                 const QString &storagePluginName) const;
    Q_INVOKABLE Sailfish::Crypto::Key constructKeyTemplate(
            Sailfish::Crypto::CryptoManager::Algorithm algorithm = Sailfish::Crypto::CryptoManager::AlgorithmAes,
            Sailfish::Crypto::CryptoManager::Operations operations = (Sailfish::Crypto::CryptoManager::OperationEncrypt
                                                                     |Sailfish::Crypto::CryptoManager::OperationDecrypt),
            Sailfish::Crypto::Key::Origin origin = Sailfish::Crypto::Key::OriginDevice) const;
    Q_INVOKABLE Sailfish::Crypto::Key::Identifier
        constructIdentifier(const QString &name,
                            const QString &collectionName,
                            const QString &storagePluginName) const;

    Q_INVOKABLE QVariant constructPbkdf2Params(const QByteArray &data,
                                               const QByteArray &salt,
                                               int iterations = 16384,
                                               int outputKeySize = 256) const;

    Q_INVOKABLE QVariant constructRsaKeygenParams() const;
    Q_INVOKABLE QVariant constructRsaKeygenParams(const QVariantMap &args) const;

    Q_INVOKABLE QVariant constructEcKeygenParams() const;
    Q_INVOKABLE QVariant constructEcKeygenParams(const QVariantMap &args) const;

    Q_INVOKABLE QVariant constructDsaKeygenParams() const;
    Q_INVOKABLE QVariant constructDsaKeygenParams(const QVariantMap &args) const;

    Q_INVOKABLE QVariant constructDhKeygenParams() const;
    Q_INVOKABLE QVariant constructDhKeygenParams(const QVariantMap &args) const;

    // QML API - allow clients to use QByteArray data in a meaningful way, not required in Qt >= 5.8
    Q_INVOKABLE QString toBase64(const QByteArray &data) const;
    Q_INVOKABLE QByteArray fromBase64(const QString &b64) const;
    Q_INVOKABLE QString stringFromBytes(const QByteArray &stringData) const; // must be valid UTF-8 data!
};

} // Plugin

} // Crypto

} // Sailfish

#endif // SAILFISHCRYPTO_QML_PLUGINTYPES_H
