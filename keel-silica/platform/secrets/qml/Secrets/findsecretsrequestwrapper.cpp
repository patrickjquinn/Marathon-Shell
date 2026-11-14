// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "findsecretsrequestwrapper.h"

#include <QtCore/QVariant>
#include <QtCore/QVariantList>

Sailfish::Secrets::Plugin::KeyIdentifier::KeyIdentifier(const QString &name, const QString &collectionName)
    : m_name(name), m_collectionName(collectionName)
{
}

QString Sailfish::Secrets::Plugin::KeyIdentifier::name() const
{
    return m_name;
}

QString Sailfish::Secrets::Plugin::KeyIdentifier::collectionName() const
{
    return m_collectionName;
}

/*!
  \qmltype FindSecretsRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client find the identifiers of secrets which match a specific filter
         from the system's secure secret storage service
  \inherits Request
 */

Sailfish::Secrets::Plugin::FindSecretsRequestWrapper::FindSecretsRequestWrapper(QObject *parent) : Sailfish::Secrets::FindSecretsRequest(parent)
{
    connect(this, &Sailfish::Secrets::FindSecretsRequest::identifiersChanged, this, &Sailfish::Secrets::Plugin::FindSecretsRequestWrapper::identifiersChanged);
}

/*!
  \qmlproperty array FindSecretsRequest::identifiers
*/

QVariantList Sailfish::Secrets::Plugin::FindSecretsRequestWrapper::identifiers() const
{
    auto resultsFromBase = Sailfish::Secrets::FindSecretsRequest::identifiers();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(KeyIdentifier(i.name(), i.collectionName())));
    }

    return results;
}

/*!
 \qmltype PluginInfoRequest
 \inqmlmodule Sailfish.Secrets
 \brief Allows a client request information about available storage, encryption and authentication plugins
 \inherits Request
 */

Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::PluginInfoRequestWrapper(QObject *parent) : Sailfish::Secrets::PluginInfoRequest(parent)
{
    connect(this, &Sailfish::Secrets::PluginInfoRequest::storagePluginsChanged, this, &Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::storagePluginsChanged);
    connect(this, &Sailfish::Secrets::PluginInfoRequest::encryptionPluginsChanged, this, &Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::encryptionPluginsChanged);
    connect(this, &Sailfish::Secrets::PluginInfoRequest::encryptedStoragePluginsChanged, this, &Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::encryptedStoragePluginsChanged);
    connect(this, &Sailfish::Secrets::PluginInfoRequest::authenticationPluginsChanged, this, &Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::authenticationPluginsChanged);
}

/*!
 \qmlproperty array PluginInfoRequest::storagePlugins
 \brief Provides information about available storage plugins.
*/

QVariantList Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::storagePlugins() const
{
    auto resultsFromBase = Sailfish::Secrets::PluginInfoRequest::storagePlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}

/*!
 \qmlproperty array PluginInfoRequest::encryptionPlugins
 \brief Provides information about available encryption plugins.
*/

QVariantList Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::encryptionPlugins() const
{
    auto resultsFromBase = Sailfish::Secrets::PluginInfoRequest::encryptionPlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}

/*!
 \qmlproperty array PluginInfoRequest::encryptedStoragePlugins
 \brief Provides information about available encrypted storage plugins.
*/

QVariantList Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::encryptedStoragePlugins() const
{
    auto resultsFromBase = Sailfish::Secrets::PluginInfoRequest::encryptedStoragePlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}

/*!
 \qmlproperty array PluginInfoRequest::authenticationPlugins
 \brief Provides information about available authentication plugins.
*/

QVariantList Sailfish::Secrets::Plugin::PluginInfoRequestWrapper::authenticationPlugins() const
{
    auto resultsFromBase = Sailfish::Secrets::PluginInfoRequest::authenticationPlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}
