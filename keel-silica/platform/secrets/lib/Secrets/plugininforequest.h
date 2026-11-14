// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_PLUGININFOREQUEST_H
#define LIBSAILFISHSECRETS_PLUGININFOREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secret.h"
#include "Secrets/secretmanager.h"
#include "Secrets/plugininfo.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QVector>

namespace Sailfish {

namespace Secrets {

class PluginInfoRequestPrivate;
class SAILFISH_SECRETS_API PluginInfoRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(QVector<Sailfish::Secrets::PluginInfo> storagePlugins READ storagePlugins NOTIFY storagePluginsChanged)
    Q_PROPERTY(QVector<Sailfish::Secrets::PluginInfo> encryptionPlugins READ encryptionPlugins NOTIFY encryptionPluginsChanged)
    Q_PROPERTY(QVector<Sailfish::Secrets::PluginInfo> encryptedStoragePlugins READ encryptedStoragePlugins NOTIFY encryptedStoragePluginsChanged)
    Q_PROPERTY(QVector<Sailfish::Secrets::PluginInfo> authenticationPlugins READ authenticationPlugins NOTIFY authenticationPluginsChanged)

public:
    PluginInfoRequest(QObject *parent = Q_NULLPTR);
    ~PluginInfoRequest();

    QVector<Sailfish::Secrets::PluginInfo> storagePlugins() const;
    QVector<Sailfish::Secrets::PluginInfo> encryptionPlugins() const;
    QVector<Sailfish::Secrets::PluginInfo> encryptedStoragePlugins() const;
    QVector<Sailfish::Secrets::PluginInfo> authenticationPlugins() const;

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void storagePluginsChanged();
    void encryptionPluginsChanged();
    void encryptedStoragePluginsChanged();
    void authenticationPluginsChanged();

private:
    QScopedPointer<PluginInfoRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(PluginInfoRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_PLUGININFOREQUEST_H
