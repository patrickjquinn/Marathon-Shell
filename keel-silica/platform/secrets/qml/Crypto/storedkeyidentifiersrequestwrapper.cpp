// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "storedkeyidentifiersrequestwrapper.h"

#include <QtCore/QVariant>
#include <QtCore/QVariantList>

Sailfish::Crypto::Plugin::KeyIdentifier::KeyIdentifier(const QString &name, const QString &collectionName)
    : m_name(name), m_collectionName(collectionName)
{
}

QString Sailfish::Crypto::Plugin::KeyIdentifier::name() const
{
    return m_name;
}

QString Sailfish::Crypto::Plugin::KeyIdentifier::collectionName() const
{
    return m_collectionName;
}

/*!
  \qmltype StoredKeyIdentifiersRequest
  \brief Allows a client request the identifiers of securely-stored keys from the system crypto service
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::StoredKeyIdentifiersRequest
*/

Sailfish::Crypto::Plugin::StoredKeyIdentifiersRequestWrapper::StoredKeyIdentifiersRequestWrapper(QObject *parent) : Sailfish::Crypto::StoredKeyIdentifiersRequest(parent)
{
    connect(this, &Sailfish::Crypto::StoredKeyIdentifiersRequest::identifiersChanged, this, &Sailfish::Crypto::Plugin::StoredKeyIdentifiersRequestWrapper::identifiersChanged);
}

/*!
  \qmlproperty array StoredKeyIdentifiersRequest::identifiers
  \brief Returns the identifiers of securely-stored keys
  \note this value is only valid if the status of the request is \c Request.Finished.
*/
QVariantList Sailfish::Crypto::Plugin::StoredKeyIdentifiersRequestWrapper::identifiers() const
{
    auto resultsFromBase = Sailfish::Crypto::StoredKeyIdentifiersRequest::identifiers();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(KeyIdentifier(i.name(), i.collectionName())));
    }

    return results;
}

/*!
  \qmltype PluginInfoRequest
  \brief Allows a client request information about available crypto and storage plugins
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::PluginInfoRequest
*/

Sailfish::Crypto::Plugin::PluginInfoRequestWrapper::PluginInfoRequestWrapper(QObject *parent) : Sailfish::Crypto::PluginInfoRequest(parent)
{
    connect(this, &Sailfish::Crypto::PluginInfoRequest::cryptoPluginsChanged, this, &Sailfish::Crypto::Plugin::PluginInfoRequestWrapper::cryptoPluginsChanged);
    connect(this, &Sailfish::Crypto::PluginInfoRequest::storagePluginsChanged, this, &Sailfish::Crypto::Plugin::PluginInfoRequestWrapper::storagePluginsChanged);
}

/*!
  \qmlproperty array PluginInfoRequest::cryptoPlugins
  \brief Returns information about available crypto plugins
  \note this value is only valid if the status of the request is \qml {Request.Finished}
*/

QVariantList Sailfish::Crypto::Plugin::PluginInfoRequestWrapper::cryptoPlugins() const
{
    auto resultsFromBase = Sailfish::Crypto::PluginInfoRequest::cryptoPlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}

/*!
  \qmlproperty array PluginInfoRequest::storagePlugins
  \brief Returns information about available (Secrets) storage plugins
  \note this value is only valid if the status of the request is \c Request.Finished
*/

QVariantList Sailfish::Crypto::Plugin::PluginInfoRequestWrapper::storagePlugins() const
{
    auto resultsFromBase = Sailfish::Crypto::PluginInfoRequest::storagePlugins();
    QVariantList results;

    for (auto i : resultsFromBase) {
        results.append(QVariant::fromValue(i));
    }

    return results;
}
