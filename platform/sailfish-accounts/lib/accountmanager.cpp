// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "accountmanager.h"
#include "accountmanager_p.h"
#include "globaltranslatorcache_p.h"
#include "globalaccountmanager_p.h"

#include "provider.h"
#include "providerhelper.h"
#include "service.h"
#include "servicetype.h"
#include "account.h"

#include <QtDebug>

// libaccounts-qt
#include <Accounts/Manager>

static const QString AccountCredentialsNeedUpdateKey = QStringLiteral("CredentialsNeedUpdate");

AccountManagerPrivate::AccountManagerPrivate(AccountManager *parent)
    : QObject(parent)
    , q(parent)
    , manager(globalAccountManager())
    , componentComplete(false)
    , busy(false)
{
    Accounts::ServiceList allServices = manager->serviceList();
    QSet<QString> serviceTypeNamesSet;
    for (int i = 0; i < allServices.size(); ++i)
        serviceTypeNamesSet.insert(allServices.at(i).serviceType());
    serviceTypeNames = serviceTypeNamesSet.values();

    manager->setTimeout(5000); // default 5 second timeout on database operations

    connect(manager, &Accounts::Manager::accountCreated,
            this, &AccountManagerPrivate::updateEverything);
    connect(manager, &Accounts::Manager::accountUpdated,
            this, &AccountManagerPrivate::updateEverything);
    connect(manager, &Accounts::Manager::accountRemoved,
            this, &AccountManagerPrivate::updateEverything);
    connect(manager, &Accounts::Manager::enabledEvent,
            this, &AccountManagerPrivate::updateEverything);
    updateEverything();
}

AccountManagerPrivate::~AccountManagerPrivate()
{
}

void AccountManagerPrivate::updateEverything()
{
    // store temp copies of all internal data, for change delta determination.
    QStringList tmpProviderNames = providerNames;
    QStringList tmpServiceNames = serviceNames;
    QList<int> tmpAccountIdentifiers = accountIdentifiers;

    // clear all internal data - except for serviceTypeNames which is static.
    providerNames.clear();
    serviceNames.clear();
    accountIdentifiers.clear();

    // reload all internal data
    Accounts::AccountIdList filteredAccounts = manager->accountList();
    for (int i = 0; i < filteredAccounts.size(); ++i) {
        accountIdentifiers.append(filteredAccounts.at(i));
    }

    Accounts::ServiceList filteredServices = manager->serviceList();
    for (int i = 0; i < filteredServices.size(); ++i) {
        const Accounts::Service &service = filteredServices.at(i);
        serviceNames.append(service.name());
        if (!providerNames.contains(service.provider())) {
            providerNames.append(service.provider());
        }
    }

    // calculate change deltas and emit appropriately.
    // Modified by Shipwright for Qt 6: QSet from a list's range (QSet::fromList is gone).
    QSet<QString> oldPN = QSet<QString>(tmpProviderNames.cbegin(), tmpProviderNames.cend());
    QSet<QString> newPN = QSet<QString>(providerNames.cbegin(), providerNames.cend());
    if (!(oldPN == newPN)) {
        emit q->providerNamesChanged();
    }

    QSet<QString> oldSN = QSet<QString>(tmpServiceNames.cbegin(), tmpServiceNames.cend());
    QSet<QString> newSN = QSet<QString>(serviceNames.cbegin(), serviceNames.cend());
    if (!(oldSN == newSN)) {
        emit q->serviceNamesChanged();
    }

    QSet<int> oldAI = QSet<int>(tmpAccountIdentifiers.cbegin(), tmpAccountIdentifiers.cend());
    QSet<int> newAI = QSet<int>(accountIdentifiers.cbegin(), accountIdentifiers.cend());
    if (!(oldAI == newAI)) {
        emit q->accountIdentifiersChanged();
    }
}

void AccountManagerPrivate::createAccountSynced()
{
    busy = false;
    Accounts::Account *account = qobject_cast<Accounts::Account*>(sender());
    if (!account) {
        return;
    }

    disconnect(account, 0, this, 0);
    emit q->accountCreated(account->id(), creatingAccounts.value(account));
    creatingAccounts.remove(account);
}

void AccountManagerPrivate::createAccountError(const Accounts::Error &error)
{
    busy = false;
    Accounts::Account *account = qobject_cast<Accounts::Account*>(sender());
    if (!account) {
        return;
    }

    disconnect(account, 0, this, 0);
    emit q->accountCreationFailed(error.message(), creatingAccounts.value(account));
    creatingAccounts.remove(account);
}

//----------------------------------------

/*!
    \qmltype AccountManager
    \instantiates AccountManager
    \inqmlmodule Sailfish.Accounts 1
    \brief Provides access to providers, services and accounts.

    The AccountManager type is intended for use by privileged applications
    and account provider plugins.  The functionality it provides is
    not useful for client applications who wish to use an account to
    access a service (such clients should use the account model instead).

    The AccountManager provides information about existing providers,
    services, and accounts.  It also allows new accounts to be created.
*/    

AccountManager::AccountManager(QObject *parent)
    : QObject(parent), d(new AccountManagerPrivate(this))
{
    SailfishAccounts::initLibTranslator();
}

AccountManager::~AccountManager()
{
}

void AccountManager::classBegin()
{
    d->componentComplete = false;
}

void AccountManager::componentComplete()
{
    d->componentComplete = true;
}

/*!
    \qmlproperty list AccountManager::serviceTypeNames
    Holds the service type names which may be used as filter values.

    The values are derived from examination of the service type of
    all services which exist in the system accounts database at
    the point in time when the AccountManager instance was created.
*/

QStringList AccountManager::serviceTypeNames() const
{
    return d->serviceTypeNames;
}

/*!
    \qmlproperty list AccountManager::providerNames
    Holds the names of all providers which exist in the system
    accounts database, which match the service type filter.
*/

QStringList AccountManager::providerNames() const
{
    return d->providerNames;
}

/*!
    \qmlproperty list AccountManager::serviceNames
    Holds the names of all services which exist in the system
    accounts database, which match the service type filter.
*/

QStringList AccountManager::serviceNames() const
{
    return d->serviceNames;
}

/*!
    \qmlproperty list AccountManager::accountIdentifiers
    Holds the identifiers of all accounts which exist in the
    system accounts database.
*/

QList<int> AccountManager::accountIdentifiers() const
{
    return d->accountIdentifiers;
}

/*!
    \qmlmethod list AccountManager::providerAccountIdentifiers(string providerName)

    Returns the list of ids of accounts provided by the provider with the
    given \a providerName (or all providers, if the given \a providerName
    is empty).
*/
QList<int> AccountManager::providerAccountIdentifiers(const QString &providerName)
{
    QList<int> returnList;
    QList<quint32> accountIdList = d->manager->accountList();
    foreach (quint32 id, accountIdList) {
        Accounts::Account *acc = Accounts::Account::fromId(d->manager, id, this);
        if (acc != nullptr) {
            if (providerName.isEmpty() || acc->providerName() == providerName) {
                returnList.append(static_cast<int>(id));
            }
        }
    }

    return returnList;
}

/*!
    \qmlsignal AccountManager::accountCreated(int accountId, string providerName)

    Emitted when account has been created.

    The \a accountId parameter contains the id of the account that was created.
    The \a providerName parameter contains the name of the account provider.
*/

/*!
    \qmlsignal AccountManager::accountCreationFailed(string message, string providerName)

    Emitted if account creation fails.

    The \a message parameter contains an error message which can be displayed to user.
    The \a providerName parameter contains the name of the account provider.
*/

/*!
    \qmlmethod bool AccountManager::createAccount(string providerName)

    Creates a new, disabled Account with the provider identified by the given
    \a providerName and stores it to the database.  The operation is
    asynchronous and on success, the accountCreated() signal will be
    emitted.  On failure, the accountCreationFailed() signal will be
    emitted.

    Returns true if the account creation process is triggered, or false if
    the manager is currently busy creating another account.
*/
bool AccountManager::createAccount(const QString &providerName)
{
    if (!d->busy) {
        d->busy = true;
        Accounts::Account *newAccount = d->manager->createAccount(providerName);
        if (!newAccount) {
            //% "Cannot find account provider"
            emit accountCreationFailed(qtTrId("sailfish_accounts-accountmanager-er_invalid_provider"), providerName);
            return true; // succeeded trigger, but failed to create the account.
        }

        d->creatingAccounts.insert(newAccount, providerName);
        connect(newAccount, &Accounts::Account::synced,
                d, &AccountManagerPrivate::createAccountSynced);
        connect(newAccount, &Accounts::Account::error,
                d, &AccountManagerPrivate::createAccountError);
        newAccount->setEnabled(false);
        newAccount->sync();
        return true;
    }

    return false;
}

/*!
    \qmlmethod ServiceType AccountManager::serviceType(string serviceTypeName)
    Returns the service type identified by the given \a serviceTypeName.
    The AccountManager owns the returned instance and will delete it on destruction.
*/
ServiceType *AccountManager::serviceType(const QString &serviceTypeName) const
{
    AccountManager *parentPtr = const_cast<AccountManager*>(this);
    Accounts::ServiceType st = d->manager->serviceType(serviceTypeName);
    ServiceType *stw = new ServiceType(st, parentPtr);
    return stw;
}

/*!
    \qmlmethod Service AccountManager::service(string serviceName)
    Returns the service identified by the given \a serviceName.
    The AccountManager has ownership of the Service adapter, and will
    delete it automatically on destruction.
*/
Service *AccountManager::service(const QString &serviceName) const
{
    AccountManager *parentPtr = const_cast<AccountManager*>(this);
    Accounts::Service srv = d->manager->service(serviceName);
    Service *newSI = new Service(srv, parentPtr);
    return newSI;
}

/*!
    \qmlmethod Provider AccountManager::provider(string providerName)
    Returns the provider identified by the given \a providerName.
    The AccountManager has ownership of the Provider adapter, and will
    delete it automatically on destruction.
*/
Provider *AccountManager::provider(const QString &providerName) const
{
    AccountManager *parentPtr = const_cast<AccountManager*>(this);
    Accounts::Provider prv = d->manager->provider(providerName);

    if (!allowedProvider(prv.tags())) {
        return nullptr;
    }

    Provider *newPI = new Provider(prv, parentPtr);
    return newPI;
}

Provider *AccountManager::providerForAccount(int accountId) const
{
    if (accountId <= 0) {
        return nullptr;
    }
    AccountManager *parentPtr = const_cast<AccountManager*>(this);
    Accounts::Account *existingAccount = Accounts::Account::fromId(d->manager, accountId, parentPtr);
    if (!existingAccount) {
        return nullptr;
    }

    Accounts::Provider prv = existingAccount->provider();
    if (!allowedProvider(prv.tags())) {
        return nullptr;
    }

    Provider *newPI = new Provider(prv, parentPtr);
    return newPI;
}

/*!
    \qmlmethod Account AccountManager::account(int accountIdentifier)

    Returns the account identified by the given \a accountIdentifier.
    The AccountManager has ownership of the Account adapter, and will
    delete it automatically on destruction.

    Returns null if no such account exists.
*/    
Account *AccountManager::account(int accountIdentifier) const
{
    AccountManager *parentPtr = const_cast<AccountManager*>(this);
    Accounts::Account *existingAccount = Accounts::Account::fromId(d->manager, accountIdentifier, parentPtr);
    if (!existingAccount) {
        return nullptr;
    }

    Account *newAcc = new Account(true, existingAccount, parentPtr);
    newAcc->classBegin();
    newAcc->setIdentifier(accountIdentifier);
    newAcc->componentComplete();
    return newAcc;
}

/*!
    \qmlmethod bool AccountManager::credentialsNeedUpdate(int accountId)

    Returns true if the global service of the account identified by
    \a accountId has \c CredentialsNeedUpdate flag and it is set.
*/
bool AccountManager::credentialsNeedUpdate(int accountId)
{
    Accounts::Account *account = Accounts::Account::fromId(d->manager, accountId, this);
    if (!account) {
        return false;
    }

    account->selectService(Accounts::Service());
    if (account->contains(AccountCredentialsNeedUpdateKey)) {
        return account->valueAsBool(AccountCredentialsNeedUpdateKey);
    }

    return false;
}

QList<int> AccountManager::enabledAccounts(const QString &providerName, const QString &serviceName)
{
    QList<int> returnList;
    if (providerName.isEmpty()) {
        return returnList;
    }

    QList<quint32> accountIdList = d->manager->accountList();
    foreach (quint32 id, accountIdList) {
        Accounts::Account *account = Accounts::Account::fromId(d->manager, id, this);
        if (account != nullptr
                && account->providerName() == providerName
                && account->isEnabled()
                && !account->valueAsBool(AccountCredentialsNeedUpdateKey)) {
            if (serviceName.isEmpty()) {
                returnList.append(static_cast<int>(id));
            } else {
                Accounts::Service service = d->manager->service(serviceName);
                if (service.isValid()) {
                    account->selectService(service);
                    if (account->isEnabled()) {
                        returnList.append(static_cast<int>(id));
                    }
                    account->selectService(Accounts::Service());
                }
            }
        }
    }

    return returnList;
}

// Provided for external use
// Internally SailfishAccounts::translatedDisplayName() can be called directly
#define TRANSLATE_DISPLAY_NAME(T) \
    QString AccountManager::translatedDisplayName(const Accounts:: T &instance) \
    { \
        SailfishAccounts::initLibTranslator(); \
        return SailfishAccounts::translatedDisplayName(instance); \
    }

TRANSLATE_DISPLAY_NAME(Provider)
TRANSLATE_DISPLAY_NAME(Service)
TRANSLATE_DISPLAY_NAME(ServiceType)
