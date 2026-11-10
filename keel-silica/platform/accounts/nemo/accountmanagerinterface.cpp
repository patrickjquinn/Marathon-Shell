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

#include "accountmanagerinterface.h"
#include "accountmanagerinterface_p.h"

#include "providerinterface.h"
#include "serviceinterface.h"
#include "servicetypeinterface.h"
#include "accountinterface.h"
#include "serviceaccountinterface.h"

#include <QtDebug>

//libaccounts-qt
#include <Accounts/Manager>

AccountManagerInterfacePrivate::AccountManagerInterfacePrivate(AccountManagerInterface *parent)
    : QObject(parent), q(parent), manager(0), timeout(3000), mustConstructManager(false), componentComplete(false)
{
    // this is terrible, but we need some way to get the list
    // of service type names which can be used for filtering.
    constructNewManager(); // no filter, currently.
    Accounts::ServiceList allServices = manager->serviceList();
    QSet<QString> serviceTypeNamesSet;
    for (int i = 0; i < allServices.size(); ++i)
        serviceTypeNamesSet.insert(allServices.at(i).serviceType());
    serviceTypeNames = serviceTypeNamesSet.values();
}

AccountManagerInterfacePrivate::~AccountManagerInterfacePrivate()
{
    delete manager;
}

void AccountManagerInterfacePrivate::constructNewManager()
{
    delete manager;
    if (serviceTypeFilter.isEmpty())
        manager = new Accounts::Manager(); // no filter.
    else
        manager = new Accounts::Manager(serviceTypeFilter);
    manager->setTimeout(timeout);

    // It turns out that the signals offered by Accounts::Manager
    // are terribly insufficient (eg, it needs providersChanged()
    // and servicesChanged() at the very least, but c'est la vie).
    connect(manager, SIGNAL(accountCreated(Accounts::AccountId)),
            this, SLOT(updateEverything()));
    connect(manager, SIGNAL(accountUpdated(Accounts::AccountId)),
            this, SLOT(updateEverything()));
    connect(manager, SIGNAL(accountRemoved(Accounts::AccountId)),
            this, SLOT(updateEverything()));
    connect(manager, SIGNAL(enabledEvent(Accounts::AccountId)),
            this, SLOT(updateEverything())); // probably not required.

    // we'll have a bunch of new data, so update everything.
    updateEverything();
}

void AccountManagerInterfacePrivate::updateEverything()
{
    if (!manager)
        return;

    // store temp copies of all internal data, for change delta determination.
    QStringList tmpProviderNames = providerNames;
    QStringList tmpServiceNames = serviceNames;
    QStringList tmpAccountIdentifiers = accountIdentifiers;

    // clear all internal data - except for serviceTypeNames which is static.
    providerNames.clear();
    serviceNames.clear();
    accountIdentifiers.clear();

    // reload all internal data
    Accounts::AccountIdList filteredAccounts = manager->accountList();
    for (int i = 0; i < filteredAccounts.size(); ++i)
        accountIdentifiers.append(QString::number(filteredAccounts.at(i)));

    Accounts::ServiceList filteredServices = manager->serviceList();
    for (int i = 0; i < filteredServices.size(); ++i) {
        const Accounts::Service &service = filteredServices.at(i);
        serviceNames.append(service.name());
    }

    Accounts::ProviderList filteredProviders = manager->providerList();
    for (int i = 0; i < filteredProviders.size(); ++i) {
        const Accounts::Provider &provider = filteredProviders.at(i);
        providerNames.append(provider.name());
    }

    // calculate change deltas and emit appropriately.
    // Modified by Shipwright for Qt 6: QSet::fromList() is gone.
    QSet<QString> oldPN = QSet<QString>(tmpProviderNames.cbegin(), tmpProviderNames.cend());
    QSet<QString> newPN = QSet<QString>(providerNames.cbegin(), providerNames.cend());
    if (!(oldPN == newPN))
        emit q->providerNamesChanged();

    QSet<QString> oldSN = QSet<QString>(tmpServiceNames.cbegin(), tmpServiceNames.cend());
    QSet<QString> newSN = QSet<QString>(serviceNames.cbegin(), serviceNames.cend());
    if (!(oldSN == newSN))
        emit q->serviceNamesChanged();

    QSet<QString> oldAI = QSet<QString>(tmpAccountIdentifiers.cbegin(), tmpAccountIdentifiers.cend());
    QSet<QString> newAI = QSet<QString>(accountIdentifiers.cbegin(), accountIdentifiers.cend());
    if (!(oldAI == newAI))
        emit q->accountIdentifiersChanged();
}

//----------------------------------------

/*!
    \qmltype AccountManager
    \instantiates AccountManagerInterface
    \inqmlmodule org.nemomobile.accounts 1
    \brief Provides access to available providers, services and accounts,
           and allows creation of new or removal of existing accounts.

    The AccountManager type is intended for use by privileged applications
    and account provider plugins.  The functionality it provides is
    not useful for client applications who wish to use an account to
    access a service (such clients should use the account model instead).

    The AccountManager provides information about existing providers,
    services, and accounts.  The information it provides can be filtered based
    on the service type.

    The AccountManager also provides functions which enable dynamic account
    instantiation and removal, however in most cases the Account type should
    be used directly instead.  Please see the documentation of the Account
    type for examples of account creation, modification and removal.
*/    

AccountManagerInterface::AccountManagerInterface(QObject *parent)
    : QObject(parent), d(new AccountManagerInterfacePrivate(this))
{
}

AccountManagerInterface::~AccountManagerInterface()
{
}

void AccountManagerInterface::classBegin()
{
    d->componentComplete = false;
}

void AccountManagerInterface::componentComplete()
{
    d->componentComplete = true;
    if (d->mustConstructManager) // if they changed the filter during initialization.
        d->constructNewManager();
}

/*!
    \qmlproperty int AccountManager::timeout
    This property holds the database synchronisation timeout limit

    The default value of the timeout is 3000 milliseconds.
*/

int AccountManagerInterface::timeout() const
{
    if (!d->manager)
        return 3000; // default 3000 msec timeout
    return d->manager->timeout();
}

void AccountManagerInterface::setTimeout(int t)
{
    if (t != d->timeout) {
        d->timeout = t;
        if (d->manager)
            d->manager->setTimeout(t);
        emit timeoutChanged();
    }
}

/*!
    \qmlproperty string AccountManager::serviceTypeFilter
    This property holds the service type name which is being used as
    a filter to limit the information reported by the manager.

    Only those providers who provide a service which matches the
    service type filter will be reported, and only those services
    which match the service type filter will be reported.
*/

QString AccountManagerInterface::serviceTypeFilter() const
{
    return d->serviceTypeFilter;
}

void AccountManagerInterface::setServiceTypeFilter(const QString &stname)
{
    if (stname != d->serviceTypeFilter) {
        d->serviceTypeFilter = stname;
        if (d->componentComplete) {
            d->constructNewManager();
            emit serviceTypeFilterChanged();
        } else {
            d->mustConstructManager = true;
        }
    }
}

/*!
    \qmlproperty QStringList AccountManager::serviceTypeNames
    Holds the service type names which may be used as filter values.

    The values are derived from examination of the service type of
    all services which exist in the system accounts database at
    the point in time when the AccountManager instance was created.
*/

QStringList AccountManagerInterface::serviceTypeNames() const
{
    return d->serviceTypeNames;
}

/*!
    \qmlproperty QStringList AccountManager::providerNames
    Holds the names of all providers which exist in the system
    accounts database, which match the service type filter.
*/

QStringList AccountManagerInterface::providerNames() const
{
    return d->providerNames;
}

/*!
    \qmlproperty QStringList AccountManager::serviceNames
    Holds the names of all services which exist in the system
    accounts database, which match the service type filter.
*/

QStringList AccountManagerInterface::serviceNames() const
{
    return d->serviceNames;
}

/*!
    \qmlproperty QStringList AccountManager::accountIdentifiers
    Holds the identifiers of all accounts which exist in the
    system accounts database.

    Note that this is a QStringList property, as QtQuick1 does
    not support sequence types like QList<int>.
*/

QStringList AccountManagerInterface::accountIdentifiers() const
{
    return d->accountIdentifiers;
}

/*!
    \qmlmethod Account* AccountManager::createAccount(const QString &providerName)

    Creates a new Account for the provider identified by the given
    \a providerName and returns it.  The AccountManager has
    ownership of the account, and will delete it automatically
    on destruction.
*/
AccountInterface *AccountManagerInterface::createAccount(const QString &providerName)
{
    Accounts::Account *newAccount = d->manager->createAccount(providerName);
    AccountInterface *newAI = new AccountInterface(newAccount, this); // the manager is always the parent of the account interface.
    newAI->classBegin();
    newAI->componentComplete();
    return newAI;
}

/*!
    \qmlmethod void AccountManager::removeAccount(Account *account)
    Removes the given account from the database.  The account will
    become invalid.
*/
void AccountManagerInterface::removeAccount(AccountInterface *account)
{
    if (!account || !account->account())
        return;

    account->remove();
}

/*!
    \qmlmethod ServiceType* AccountManager::serviceType(const QString &serviceTypeName)
    Returns the service type identified by the given \a serviceTypeName.
    The AccountManager owns the returned instance and will delete it on destruction.
*/
ServiceTypeInterface *AccountManagerInterface::serviceType(const QString &serviceTypeName) const
{
    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    Accounts::ServiceType st = d->manager->serviceType(serviceTypeName);
    ServiceTypeInterface *sti = new ServiceTypeInterface(st, parentPtr);
    return sti;
}

/*!
    Returns the service identified by the given \a serviceName.
    The AccountManager has ownership of the Service adapter, and will
    delete it automatically on destruction.
*/
ServiceInterface *AccountManagerInterface::service(const QString &serviceName) const
{
    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    Accounts::Service srv = d->manager->service(serviceName);
    ServiceInterface *newSI = new ServiceInterface(srv, parentPtr);
    return newSI;
}

/*!
    \qmlmethod Provider* AccountManager::provider(const QString &providerName)
    Returns the provider identified by the given \a providerName.
    The AccountManager has ownership of the Provider adapter, and will
    delete it automatically on destruction.
*/
ProviderInterface *AccountManagerInterface::provider(const QString &providerName) const
{
    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    Accounts::Provider prv = d->manager->provider(providerName);
    ProviderInterface *newPI = new ProviderInterface(prv, parentPtr);
    return newPI;
}

/*!
    \qmlmethod Account* AccountManager::account(const QString &accountIdentifier)
    \overload
*/
AccountInterface *AccountManagerInterface::account(const QString &accountIdentifier) const
{
    bool ok = false;
    Accounts::AccountId id = accountIdentifier.toInt(&ok);
    if (!ok)
        return 0;
    return account(id);
}

/*!
    \qmlmethod Account* AccountManager::account(int accountIdentifier)

    Returns the account identified by the given \a accountIdentifier.
    The AccountManager has ownership of the Account adapter, and will
    delete it automatically on destruction.

    Returns null if no such account exists.
*/    
AccountInterface *AccountManagerInterface::account(int accountIdentifier) const
{
    Accounts::Account *existingAccount = d->manager->account(accountIdentifier);
    if (!existingAccount)
        return 0;

    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    AccountInterface *newAI = new AccountInterface(existingAccount, parentPtr);
    newAI->classBegin();
    newAI->componentComplete();
    return newAI;
}

/*!
    \qmlmethod ServiceAccount* AccountManager::serviceAccount(const QString &accountIdentifier, const QString &serviceName)
    \overload
*/
ServiceAccountInterface *AccountManagerInterface::serviceAccount(const QString &accountIdentifier, const QString &serviceName) const
{
    bool ok = false;
    Accounts::AccountId id = accountIdentifier.toInt(&ok);
    if (!ok) {
        qWarning() << Q_FUNC_INFO << "Not a valid account identifier:" << accountIdentifier;
        return 0;
    }
    return serviceAccount(id, serviceName);
}

/*!
    \qmlmethod ServiceAccount* AccountManager::serviceAccount(int accountIdentifier, const QString &serviceName)

    Returns the ServiceAccount identified by the given \a accountIdentifier
    which may be used with the service identified by the given \a serviceName.
    The AccountManager has ownership of the ServiceAccount adapter, and will
    delete it automatically on destruction.

    Returns null if no such account exists.
*/
ServiceAccountInterface *AccountManagerInterface::serviceAccount(int accountIdentifier, const QString &serviceName) const
{
    Accounts::Account *existingAccount = d->manager->account(accountIdentifier);
    if (!existingAccount) {
        qWarning() << Q_FUNC_INFO << "Not a valid account identifier:" << accountIdentifier;
        return 0;
    }

    Accounts::Service srv = d->manager->service(serviceName);
    if (!srv.isValid()) {
        qWarning() << Q_FUNC_INFO << "Not a valid service:" << serviceName;
        return 0;
    }

    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    Accounts::AccountService *srvAcc = new Accounts::AccountService(existingAccount, srv);
    if (!srvAcc) {
        qWarning() << Q_FUNC_INFO << "Account not able to be used with the given service:" << serviceName;
        return 0;
    }

    ServiceAccountInterface *newSAI = new ServiceAccountInterface(srvAcc, ServiceAccountInterface::HasOwnership, parentPtr);
    return newSAI;
}

/*!
    \qmlmethod ServiceAccount* AccountManager::serviceAccountFromProvider(const QString &serviceName, const QString &providerName)

    Returns the first enabled ServiceAccount which is provided by the provider identified by
    the given \a providerName.  If the \a serviceName is specified, the ServiceAccount returned
    will be the ServiceAccount for that particular service, or null if it does not exist or is not
    enabled.  The AccountManager has ownership of the ServiceAccount adapter, and will delete it
    automatically on destruction.

    Returns null if no such account exists, or if the \a providerName does not identify a valid
    provider, or if the \a serviceName is given and does not identity a valid service or if the
    account is not enabled with that service.
*/
ServiceAccountInterface *AccountManagerInterface::serviceAccountFromProvider(const QString &providerName, const QString &serviceName) const
{
    Accounts::Provider prv = d->manager->provider(providerName);
    if (!prv.isValid()) {
        qWarning() << Q_FUNC_INFO << "No such provider:" << providerName;
        return 0;
    }

    Accounts::AccountIdList enabledAccounts;
    Accounts::Service srv;
    if (!serviceName.isEmpty()) {
        srv = d->manager->service(serviceName);
        if (!srv.isValid()) {
            qWarning() << Q_FUNC_INFO << "No such service:" << serviceName;
            return 0;
        }
        enabledAccounts = d->manager->accountListEnabled(srv.serviceType());
    } else {
        enabledAccounts = d->manager->accountListEnabled();
    }

    Accounts::Account *whichAccount = 0;
    foreach (Accounts::AccountId aid, enabledAccounts) {
        Accounts::Account *acc = d->manager->account(aid);
        if (acc->providerName() == prv.name()) {
            if (!acc->enabled())
                continue; // this shouldn't be possible, but just in case...

            if (srv.isValid()) {
                acc->selectService(srv);
                if (!acc->enabled()) {
                    continue;
                }

                // we have a valid account which is enabled with the service.
                whichAccount = acc;
                break;
            }

            // no service was specified, use any enabled account service.
            Accounts::ServiceList enabledServices = acc->enabledServices();
            if (!enabledServices.isEmpty()) {
                whichAccount = acc;
                srv = enabledServices.at(0);
                break;
            }
        }
    }

    if (!whichAccount) {
        if (srv.isValid())
            qWarning() << Q_FUNC_INFO << "No enabled account from provider:" << providerName << "for service:" << srv.name();
        else
            qWarning() << Q_FUNC_INFO << "No enabled account from provider:" << providerName;
        return 0;
    }

    AccountManagerInterface *parentPtr = const_cast<AccountManagerInterface*>(this);
    Accounts::AccountService *srvAcc = new Accounts::AccountService(whichAccount, srv);
    if (!srvAcc) {
        qWarning() << Q_FUNC_INFO << "Unable to create service account from provider:" << providerName << "for service:" << srv.name();
        return 0;
    }

    ServiceAccountInterface *newSAI = new ServiceAccountInterface(srvAcc, ServiceAccountInterface::HasOwnership, parentPtr);
    return newSAI;
}

