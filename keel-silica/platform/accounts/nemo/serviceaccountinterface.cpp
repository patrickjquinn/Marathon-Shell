// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd. <chris.adams@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "serviceaccountinterface.h"
#include "serviceaccountinterface_p.h"
#include "accountvalueencoding_p.h"

#include "serviceinterface.h"
#include "providerinterface.h"
#include "authdatainterface.h"

//libaccounts-qt
#include <Accounts/AccountService>
#include <Accounts/Account>
#include <Accounts/Manager>

ServiceAccountInterfacePrivate::ServiceAccountInterfacePrivate(ServiceAccountInterface *parent, Accounts::AccountService *s, bool ownsAccountService)
    : QObject(parent), q(parent), serviceAccount(s), hasOwnership(ownsAccountService)
{
    authDataInterface = new AuthDataInterface(serviceAccount->authData(), this);
    serviceInterface = new ServiceInterface(serviceAccount->service(), this);
    providerInterface = new ProviderInterface(serviceAccount->account()->manager()->provider(serviceAccount->account()->providerName()), this);
}

ServiceAccountInterfacePrivate::~ServiceAccountInterfacePrivate()
{
    delete authDataInterface;
    delete serviceInterface;
    delete providerInterface;
    if (hasOwnership)
        delete serviceAccount;
}

void ServiceAccountInterfacePrivate::updateConfigurationValues()
{
    configurationValues.clear();
    QStringList allKeys = serviceAccount->allKeys();
    foreach (const QString &key, allKeys) {
        QVariant currentValue;
        currentValue = serviceAccount->value(key, 0);
        configurationValues.insert(key, currentValue);
    }

    emit q->configurationValuesChanged();
}

//------------------------------


/*!
    \qmltype ServiceAccount
    \instantiates ServiceAccountInterface
    \inqmlmodule org.nemomobile.accounts 1
    \brief An account which can be used with a particular service

    Each account in the accounts database can support one or more
    services.  When using an account, it must be used with a
    particular service.  A ServiceAccount provides the service-specific
    information and functionality for a particular account.

    This type is intended for use by clients.  Applications can retrieve
    ServiceAccount instances from the account model, and retrieve
    information about associated any ServiceAccountIdentity associated
    with the account for this service (to sign on to the service).

    Service-specific account configuration settings may also be set via
    the ServiceAccount type.
*/

ServiceAccountInterface::ServiceAccountInterface(Accounts::AccountService* serviceAccount, ServiceAccountInterface::OwnershipSemantic os, QObject *parent)
    : QObject(parent), d(new ServiceAccountInterfacePrivate(this, serviceAccount, (os == ServiceAccountInterface::HasOwnership)))
{
    connect(serviceAccount, SIGNAL(changed()), d, SLOT(updateConfigurationValues()));
    connect(serviceAccount, SIGNAL(enabled(bool)), this, SIGNAL(enabledChanged()));
}

ServiceAccountInterface::~ServiceAccountInterface()
{
}

/*!
    \qmlproperty bool ServiceAccount::enabled
    Returns true if the account is enabled for use with the service.
*/

bool ServiceAccountInterface::enabled() const
{
    if (d->serviceAccount)
        return d->serviceAccount->enabled();
    return false;
}

/*!
    \qmlproperty int ServiceAccount::identifier
    Returns the identifier of the account, or zero if not initialized
*/

int ServiceAccountInterface::identifier() const
{
    if (d->serviceAccount && d->serviceAccount->account())
        return d->serviceAccount->account()->id();
    return 0;
}

/*!
    \qmlproperty AuthData* ServiceAccount::authData
    Returns information about the authentication credentials
    associated with the account for the service.
*/

AuthDataInterface *ServiceAccountInterface::authData() const
{
    return d->authDataInterface;
}

/*!
    \qmlproperty Service* ServiceAccount::service
    Returns the service with which this ServiceAccount is associated
*/

ServiceInterface *ServiceAccountInterface::service() const
{
    return d->serviceInterface;
}

/*!
    \qmlproperty Provider* ServiceAccount::provider
    Returns the provider of the account and the service
*/

ProviderInterface *ServiceAccountInterface::provider() const
{
    return d->providerInterface;
}

/*!
    \qmlmethod void ServiceAccount::setConfigurationValue(const QString &key, const QVariant &value)

    Sets the configuration setting for the key \a key to the
    given value \a value.  This operation may be synchronous or asynchronous.
    If it succeeds, the configurationValuesChanged() signal will be emitted.
*/
void ServiceAccountInterface::setConfigurationValue(const QString &key, const QVariant &value)
{
    if (value.type() == QVariant::List) {
        setConfigurationValue(key, value.toStringList());
        return;
    }

    if (d->serviceAccount) {
        d->serviceAccount->setValue(key, value);
        if (d->serviceAccount->account()) {
            d->serviceAccount->account()->sync();
        }
    }
}

/*!
    \qmlmethod void ServiceAccount::removeConfigurationValue(const QString &key)

    Removes the configuration setting key \a key and any
    associated values.  This operation may be synchronous or asynchronous.
    If it succeeds, the configurationValuesChanged() signal will be emitted.
*/
void ServiceAccountInterface::removeConfigurationValue(const QString &key)
{
    if (d->serviceAccount) {
        d->serviceAccount->remove(key);
        if (d->serviceAccount->account()) {
            d->serviceAccount->account()->sync();
        }
    }
}

/*!
    \qmlproperty QVariantMap ServiceAccount::configurationValues
    Holds the service-specific account settings of this ServiceAccount
*/

QVariantMap ServiceAccountInterface::configurationValues() const
{
    return d->configurationValues;
}


/*!
    \qmlmethod QVariantMap ServiceAccount::unrelatedValues()

    Holds all of the account settings of this account,
    even those which are not directly related to the service.
    Some settings may be applicable to multiple services, and thus are
    stored in non-service-specific settings.
*/
QVariantMap ServiceAccountInterface::unrelatedValues() const
{
    // All key/value pairs from the account.  Just in case something is stored
    // at the account level, rather than at the service-account level.
    // One example is the email address for a pop3 service - the email address
    // is usually the username for the entire account, not just the service.
    // We don't expose unrelatedValues as a property, because Accounts::Account
    // doesn't emit a changed() signal the way Accounts::AccountService does.
    // Since we can't notify on changes, let's not pretend it's a property.
    Accounts::Account *acct = d->serviceAccount->account();
    if (!acct)
        return QVariantMap();
    Accounts::Service srv = acct->selectedService();
    acct->selectService(Accounts::Service());
    QStringList allKeys = acct->allKeys();
    QVariantMap unrelatedValues;
    foreach (const QString &key, allKeys)
        unrelatedValues.insert(key, acct->value(key, QVariant(), 0));
    acct->selectService(srv);

    return unrelatedValues;
}

/*!
    \qmlmethod QString ServiceAccount::encodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const

    Encodes the given \a value with the specified \a key using the specified \a scheme.
    If the \a scheme is empty or invalid, the value will be encoded with Base64 and the
    key will be ignored.

    The implementation of each scheme is non-standard and a value encoded with this
    method shouldn't be assumed to be decodable via a method other than calling
    \c decodeConfigurationValue().

    This method can be used to encode values which shouldn't be stored as plain text
    in an account configuration.  Note that this method does NOT provide any security,
    nor is it intended for use in cryptography or authentication; it exists merely as
    a convenience for application authors.

    Valid schemes are:
    \list
    \li "base64" - \a key is ignored
    \li "rot" - \a key is ignored
    \li "xor" - \a key is used if all characters are between 'a' and 'z', or "nemo" by default
    \endlist
*/
QString ServiceAccountInterface::encodeConfigurationValue(const QString &value, const QString &scheme, const QString &key) const
{
    return encodeValue(value, scheme, key); // from accountvalueencoding_p.h
}

/*!
    \qmlmethod QString ServiceAccount::decodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const

    Decodes the given \a value with the specified \a key using the specified \a scheme.
    This method can be used to decode values which were previously encoded with encode().
*/
QString ServiceAccountInterface::decodeConfigurationValue(const QString &value, const QString &scheme, const QString &key) const
{
    return decodeValue(value, scheme, key); // from accountvalueencoding_p.h
}

