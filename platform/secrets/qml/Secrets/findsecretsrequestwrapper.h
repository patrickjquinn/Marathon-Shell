// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef SAILFISHSECRETS_QML_FINDSECRETSREQUESTWRAPPER_H
#define SAILFISHSECRETS_QML_FINDSECRETSREQUESTWRAPPER_H

#include "Secrets/result.h"
#include "Secrets/secret.h"

#include "Secrets/findsecretsrequest.h"
#include "Secrets/plugininforequest.h"

#include <QtCore/QVariant>
#include <QtCore/QVariantList>

namespace Sailfish {

namespace Secrets {

namespace Plugin {

class KeyIdentifier {
    Q_GADGET
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString collectionName READ collectionName CONSTANT)

public:
    KeyIdentifier() = default;
    KeyIdentifier(const QString &name, const QString &collectionName);
    QString name() const;
    QString collectionName() const;

private:
    QString m_name;
    QString m_collectionName;
};

class FindSecretsRequestWrapper : public Sailfish::Secrets::FindSecretsRequest {
    Q_OBJECT
    Q_PROPERTY(QVariantList identifiers READ identifiers NOTIFY identifiersChanged)

public:
    FindSecretsRequestWrapper(QObject *parent = Q_NULLPTR);
    QVariantList identifiers() const;

Q_SIGNALS:
    void identifiersChanged();
};

class PluginInfoRequestWrapper : public Sailfish::Secrets::PluginInfoRequest {
    Q_OBJECT
    Q_PROPERTY(QVariantList storagePlugins READ storagePlugins NOTIFY storagePluginsChanged)
    Q_PROPERTY(QVariantList encryptionPlugins READ encryptionPlugins NOTIFY encryptionPluginsChanged)
    Q_PROPERTY(QVariantList encryptedStoragePlugins READ encryptedStoragePlugins NOTIFY encryptedStoragePluginsChanged)
    Q_PROPERTY(QVariantList authenticationPlugins READ authenticationPlugins NOTIFY authenticationPluginsChanged)

public:
    PluginInfoRequestWrapper(QObject *parent = Q_NULLPTR);
    QVariantList storagePlugins() const;
    QVariantList encryptionPlugins() const;
    QVariantList encryptedStoragePlugins() const;
    QVariantList authenticationPlugins() const;

Q_SIGNALS:
    void storagePluginsChanged();
    void encryptionPluginsChanged();
    void encryptedStoragePluginsChanged();
    void authenticationPluginsChanged();
};

} // Plugin

} // Secrets

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Secrets::Plugin::KeyIdentifier)

#endif // SAILFISHSECRETS_QML_FINDSECRETSREQUESTWRAPPER_H
