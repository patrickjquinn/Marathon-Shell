// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/cryptodaemonconnection_p.h"
#include "Crypto/cryptodaemonconnection_p_p.h"
#include "Crypto/serialization_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/result.h"
#include "Crypto/key.h"
#include "Crypto/plugininfo.h"
#include "Crypto/storedkeyrequest.h"
#include "Crypto/cipherrequest.h"
#include "Crypto/lockcoderequest.h"

#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusMetaType>
#include <QStandardPaths>

Q_LOGGING_CATEGORY(lcSailfishCryptoDaemonConnection, "org.sailfishos.crypto.daemon.connection", QtWarningMsg)

Sailfish::Crypto::CryptoDaemonConnectionPrivate::CryptoDaemonConnectionPrivate(CryptoDaemonConnection *parent)
    : QObject(parent)
    , m_connection(QLatin1String("org.sailfishos.crypto.daemon.invalidConnection"))
    , m_parent(parent)
{
}

bool Sailfish::Crypto::CryptoDaemonConnectionPrivate::connect()
{
    if (m_connection.isConnected()) {
        return true;
    }

    // Step one: query the crypto daemon's "discovery" SessionBusObject for the PeerToPeer address.
    QString address(QStringLiteral("unix:path=") + QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/sailfishsecretsd/p2pSocket"));
    QDBusInterface iface("org.sailfishos.crypto.daemon.discovery",
                         "/Sailfish/Crypto/Discovery",
                         "org.sailfishos.crypto.daemon.discovery",
                         QDBusConnection::sessionBus());
    if (iface.isValid()) {
        QDBusReply<QString> reply = iface.call("peerToPeerAddress");
        if (reply.isValid()) {
            address = reply.value();
        } else {
            qCDebug(lcSailfishCryptoDaemonConnection) << "Unable to query the peer to peer socket address from the crypto daemon!  Using fallback address.";
        }
    } else {
        qCDebug(lcSailfishCryptoDaemonConnection) << "Unable to connect to the crypto daemon discovery service!  Using fallback address.";
    }

    // Step two: connect to the PeerToPeer address.
    static int connectionCount = 0;
    const QString name = QString::fromLatin1("sailfishcryptod-connection-%1").arg(connectionCount++);

    qCDebug(lcSailfishCryptoDaemonConnection) << "Connecting to crypto daemon via p2p address:" << address
                                              << "with connection name:" << name;

    QDBusConnection p2pc = QDBusConnection::connectToPeer(address, name);
    if (!p2pc.isConnected()) {
        qCWarning(lcSailfishCryptoDaemonConnection) << "Unable to connect to crypto daemon:" << p2pc.lastError()
                                                    << p2pc.lastError().type() << p2pc.lastError().name();
        return false;
    }

    m_connection = p2pc;
    m_connection.connect(QString(), // any service
                         QLatin1String("/org/freedesktop/DBus/Local"),
                         QLatin1String("org.freedesktop.DBus.Local"),
                         QLatin1String("Disconnected"),
                         this, SLOT(disconnected()));

    qCDebug(lcSailfishCryptoDaemonConnection) << "Connected to crypto daemon via connection:" << m_connection.name();

    return true;
}

void Sailfish::Crypto::CryptoDaemonConnectionPrivate::disconnected()
{
    qCDebug(lcSailfishCryptoDaemonConnection) << "Disconnected from crypto daemon via connection:" << m_connection.name();
    if (!m_parent.isNull()) {
        emit m_parent->disconnected();
    }
}

// -------------------------------------------

Sailfish::Crypto::CryptoDaemonConnection::CryptoDaemonConnection()
    : m_data(Q_NULLPTR)
    , m_refCount(0)
{
    registerDBusTypes();
}

static QPointer<Sailfish::Crypto::CryptoDaemonConnection> connectionInstance;
Sailfish::Crypto::CryptoDaemonConnection::~CryptoDaemonConnection()
{
    m_data->deleteLater();
    m_data = Q_NULLPTR;
}

Sailfish::Crypto::CryptoDaemonConnection* Sailfish::Crypto::CryptoDaemonConnection::instance()
{
    if (!connectionInstance) {
        connectionInstance = new Sailfish::Crypto::CryptoDaemonConnection;
    }

    (void)connectionInstance->m_refCount.ref();
    if (!connectionInstance->m_refCount.deref()) {
        connectionInstance->m_data = new Sailfish::Crypto::CryptoDaemonConnectionPrivate(connectionInstance);
    }
    connectionInstance->m_refCount.ref();
    return connectionInstance;
}

void Sailfish::Crypto::CryptoDaemonConnection::releaseInstance()
{
    if (connectionInstance) {
        if (!connectionInstance->m_refCount.deref()) {
            connectionInstance->deleteLater();
        }
    }
}

bool Sailfish::Crypto::CryptoDaemonConnection::connect()
{
    (void)m_refCount.ref();
    if (m_refCount.deref()) {
        return m_data->connect();
    }
    return false;
}

QDBusConnection *Sailfish::Crypto::CryptoDaemonConnection::connection()
{
    (void)m_refCount.ref();
    if (m_refCount.deref()) {
        return m_data->connection();
    }
    return Q_NULLPTR;
}

// caller takes ownership of the returned instance, alternatively it is parented to the given \a parent object.
QDBusInterface *Sailfish::Crypto::CryptoDaemonConnection::createInterface(const QString &objectPath, const QString &interface, QObject *parent)
{
    QDBusInterface *retn = new QDBusInterface("org.sailfishos.crypto.daemon", objectPath, interface, m_data->m_connection, parent);
    retn->setTimeout(180000); // some of the permission flows can take arbitrarily long (user input)
    return retn;
}

void Sailfish::Crypto::CryptoDaemonConnection::registerDBusTypes()
{
    qRegisterMetaType<Sailfish::Crypto::Key::Origin>("Sailfish::Crypto::Key::Origin");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::Algorithm>("Sailfish::Crypto::CryptoManager::Algorithm");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::BlockMode>("Sailfish::Crypto::CryptoManager::BlockMode");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::EncryptionPadding>("Sailfish::Crypto::CryptoManager::EncryptionPadding");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::SignaturePadding>("Sailfish::Crypto::CryptoManager::SignaturePadding");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::DigestFunction>("Sailfish::Crypto::CryptoManager::Digest");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::Operation>("Sailfish::Crypto::CryptoManager::Operation");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::VerificationStatusType>("Sailfish::Crypto::CryptoManager::VerificationStatusType");
    qRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::BlockMode> >("QVector<Sailfish::Crypto::CryptoManager::BlockMode>");
    qRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::EncryptionPadding> >("QVector<Sailfish::Crypto::CryptoManager::EncryptionPadding>");
    qRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::SignaturePadding> >("QVector<Sailfish::Crypto::CryptoManager::SignaturePadding>");
    qRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::DigestFunction> >("QVector<Sailfish::Crypto::CryptoManager::DigestFunction>");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::Operations>("Sailfish::Crypto::CryptoManager::Operations");
    qRegisterMetaType<Sailfish::Crypto::CryptoManager::VerificationStatus>("Sailfish::Crypto::CryptoManager::VerificationStatus");
    qRegisterMetaType<Sailfish::Crypto::Key::Identifier>("Sailfish::Crypto::Key::Identifier");
    qRegisterMetaType<QVector<Sailfish::Crypto::Key::Identifier> >("QVector<Sailfish::Crypto::Key::Identifier>");
    qRegisterMetaType<Sailfish::Crypto::Key::FilterData>("Sailfish::Crypto::Key::FilterData");
    qRegisterMetaType<Sailfish::Crypto::Key>("Sailfish::Crypto::Key");
    qRegisterMetaType<Sailfish::Crypto::Result>("Sailfish::Crypto::Result");
    qRegisterMetaType<Sailfish::Crypto::Key::Component>("Sailfish::Crypto::Key::Component");
    qRegisterMetaType<Sailfish::Crypto::Key::Components>("Sailfish::Crypto::Key::Components");
    qRegisterMetaType<Sailfish::Crypto::CipherRequest::CipherMode>("Sailfish::Crypto::CipherRequest::CipherMode");
    qRegisterMetaType<Sailfish::Crypto::KeyPairGenerationParameters>("Sailfish::Crypto::KeyPairGenerationParameters");
    qRegisterMetaType<Sailfish::Crypto::KeyPairGenerationParameters::KeyPairType>("Sailfish::Crypto::KeyPairGenerationParameters::KeyPairType");
    qRegisterMetaType<Sailfish::Crypto::KeyDerivationParameters>("Sailfish::Crypto::KeyDerivationParameters");
    qRegisterMetaType<Sailfish::Crypto::InteractionParameters>("Sailfish::Crypto::InteractionParameters");
    qRegisterMetaType<Sailfish::Crypto::InteractionParameters::PromptText>("Sailfish::Crypto::InteractionParameters::PromptText");
    qRegisterMetaType<Sailfish::Crypto::LockCodeRequest::LockCodeTargetType>("Sailfish::Crypto::LockCodeRequest::LockCodeTargetType");
    qRegisterMetaType<Sailfish::Crypto::LockCodeRequest::LockStatus>("Sailfish::Crypto::LockCodeRequest::LockStatus");
    qRegisterMetaType<Sailfish::Crypto::PluginInfo>("Sailfish::Crypto::PluginInfo");
    qRegisterMetaType<QVector<Sailfish::Crypto::PluginInfo> >("QVector<Sailfish::Crypto::PluginInfo>");

    qDBusRegisterMetaType<Sailfish::Crypto::Key::Origin>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::Algorithm>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::BlockMode>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::EncryptionPadding>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::SignaturePadding>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::DigestFunction>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::Operation>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::VerificationStatusType>();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::BlockMode> >();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::EncryptionPadding> >();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::SignaturePadding> >();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::CryptoManager::DigestFunction> >();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::Operations>();
    qDBusRegisterMetaType<Sailfish::Crypto::CryptoManager::VerificationStatus>();
    qDBusRegisterMetaType<Sailfish::Crypto::Key::Identifier>();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::Key::Identifier> >();
    qDBusRegisterMetaType<Sailfish::Crypto::Key>();
    qDBusRegisterMetaType<Sailfish::Crypto::Result>();
    qDBusRegisterMetaType<Sailfish::Crypto::Key::Component>();
    qDBusRegisterMetaType<Sailfish::Crypto::Key::Components>();
    qDBusRegisterMetaType<Sailfish::Crypto::CipherRequest::CipherMode>();
    qDBusRegisterMetaType<Sailfish::Crypto::KeyPairGenerationParameters>();
    qDBusRegisterMetaType<Sailfish::Crypto::KeyPairGenerationParameters::KeyPairType>();
    qDBusRegisterMetaType<Sailfish::Crypto::KeyDerivationParameters>();
    qDBusRegisterMetaType<Sailfish::Crypto::InteractionParameters>();
    qDBusRegisterMetaType<Sailfish::Crypto::InteractionParameters::PromptText>();
    qDBusRegisterMetaType<Sailfish::Crypto::LockCodeRequest::LockCodeTargetType>();
    qDBusRegisterMetaType<Sailfish::Crypto::LockCodeRequest::LockStatus>();
    qDBusRegisterMetaType<Sailfish::Crypto::PluginInfo>();
    qDBusRegisterMetaType<QVector<Sailfish::Crypto::PluginInfo> >();
}
