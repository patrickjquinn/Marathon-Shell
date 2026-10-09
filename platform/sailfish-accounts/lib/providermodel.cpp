// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2017 - 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "providermodel.h"
#include "provider.h"
#include "providerhelper.h"
#include "globalaccountmanager_p.h"
#include "globaltranslatorcache_p.h"

#include <QDebug>
#include <QHash>

//libaccounts-qt
#include <Accounts/Manager>

class ProviderModel::ProviderModelPrivate : public QObject
{
    Q_OBJECT
public:
    ProviderModelPrivate(ProviderModel *parent);

    bool providerMatchesProviderFilter(const QString &providerName);
    bool providerMatchesServiceFilter(const QString &providerName);
    bool canCreateAccountForProvider(const Accounts::Provider &provider) const;
    bool hasFilters() const;

    void reloadProviders();
    void reloadAccountCounts();
    void updateAccountCount(Accounts::AccountId id);

    static QString retrieveDescription(const Accounts::Provider &provider);

    QList<Accounts::Provider> providerList;
    QList<Accounts::Provider> filteredProviderList;
    QHash<QString, QStringList> providerServiceTypes;
    QHash<int, QByteArray> headerData;
    QHash<QString, int> accountCounts;
    QStringList filteredProviderNames;
    QStringList serviceFilters;
    QStringList providerFilters;
    QStringList otherExcludedProviders;
    bool excludeProvidersForUncreatableAccounts = false;
    bool componentComplete = false;

    Q_DECLARE_PUBLIC(ProviderModel)
    ProviderModel *q_ptr;
};

ProviderModel::ProviderModelPrivate::ProviderModelPrivate(ProviderModel *parent)
    : QObject(parent)
    , q_ptr(parent)
{
}

bool ProviderModel::ProviderModelPrivate::providerMatchesProviderFilter(const QString &providerName)
{
    return providerFilters.isEmpty() || providerFilters.contains(providerName);
}

bool ProviderModel::ProviderModelPrivate::providerMatchesServiceFilter(const QString &providerName)
{
    if (serviceFilters.isEmpty()) {
        return true;
    }
    const QStringList supportedServices = providerServiceTypes[providerName];
    if (!supportedServices.isEmpty()) {
        Q_FOREACH (const QString &service, serviceFilters) {
            if (supportedServices.contains(service, Qt::CaseInsensitive)) {
                return true;
            }
        }
    }
    return false;
}

bool ProviderModel::ProviderModelPrivate::canCreateAccountForProvider(const Accounts::Provider &provider) const
{
    if (!excludeProvidersForUncreatableAccounts) {
        return true;
    }

    if (!allowedProvider(provider.tags())) {
        return false;
    }

    return !provider.isSingleAccount() || accountCounts.value(provider.name(), 0) == 0;
}

bool ProviderModel::ProviderModelPrivate::hasFilters() const
{
    return !providerFilters.isEmpty()
            || !serviceFilters.isEmpty()
            || excludeProvidersForUncreatableAccounts
            || !otherExcludedProviders.isEmpty();
}

void ProviderModel::ProviderModelPrivate::reloadProviders()
{
    Q_Q(ProviderModel);

    if (!componentComplete) {
        return;
    }

    QList<Accounts::Provider> result;
    const QList<Accounts::Provider> &providers = filteredProviderList;
    QStringList names;
    const int prevCount = q->rowCount();

    for (const Accounts::Provider &provider : providers) {
        const QString &providerName = provider.name();
        if (providerMatchesProviderFilter(providerName)
                && providerMatchesServiceFilter(providerName)
                && canCreateAccountForProvider(provider)
                && !otherExcludedProviders.contains(providerName)) {
            result.append(provider);
            names.append(providerName);
        }
    }

    q->beginResetModel();
    filteredProviderList = result;
    q->endResetModel();

    if (filteredProviderNames != names) {
        filteredProviderNames = names;
        emit q->providerNamesChanged();
    }

    if (prevCount != result.count()) {
        emit q->rowCountChanged();
    }
}

void ProviderModel::ProviderModelPrivate::reloadAccountCounts()
{
    if (!excludeProvidersForUncreatableAccounts) {
        return;
    }
    accountCounts.clear();
    Accounts::Manager *manager = globalAccountManager();
    const QList<quint32> accountIdList = manager->accountList();
    for (quint32 id : accountIdList) {
        updateAccountCount(id);
    }
}


void ProviderModel::ProviderModelPrivate::updateAccountCount(Accounts::AccountId id) {
    if (!excludeProvidersForUncreatableAccounts) {
        return;
    }
    Accounts::Manager *manager = globalAccountManager();
    Accounts::Account *account = manager->account(id);
    if (account) {
        const QString providerName = account->providerName();
        accountCounts.insert(providerName, accountCounts.value(providerName, 0) + 1);
    }
}

QString ProviderModel::ProviderModelPrivate::retrieveDescription(const Accounts::Provider &provider)
{
    QDomElement root = provider.domDocument().documentElement();
    QDomElement descriptionElement = root.firstChildElement("description");
    if (!descriptionElement.text().isEmpty()) {
        return descriptionElement.text();
    } else {
        return QString();
    }
}

//-----------------------

/*!
    \qmltype ProviderModel
    \instantiates ProviderModel
    \inherits QAbstractListModel
    \inqmlmodule Sailfish.Accounts 1
    \brief Provides a model of existing account providers

    The ProviderModel can be used to provide account provider data to a view.
    For each account provider in the database, it exposes the following roles:
    \list
    \li \c providerName
    \li \c providerDisplayName
    \li \c providerDescription
    \li \c providerIcon
    \endlist
*/

ProviderModel::ProviderModel(QObject* parent)
    : QAbstractListModel(parent)
    , d_ptr(new ProviderModelPrivate(this))
{
    Q_D(ProviderModel);

    d->headerData.insert(ProviderNameRole, "providerName");
    d->headerData.insert(ProviderDisplayNameRole, "providerDisplayName");
    d->headerData.insert(ProviderDescriptionRole, "providerDescription" );
    d->headerData.insert(ProviderIconRole, "providerIcon");
    d->headerData.insert(ProviderIsSingleAccountRole, "providerIsSingleAccount");

    Accounts::Manager *m = globalAccountManager();
    Accounts::ServiceList allServices = m->serviceList(); // force reload of service files.
    Accounts::ProviderList providers = m->providerList();

    connect(m, &Accounts::Manager::accountCreated,
            d, &ProviderModelPrivate::updateAccountCount);

    foreach (const Accounts::Provider &provider, providers) {
        for (QList<Accounts::Service>::iterator it = allServices.begin(); it != allServices.end();) {
            const Accounts::Service &service = *it;
            if (service.provider() == provider.name()) {
                d->providerServiceTypes[service.provider()].append(service.serviceType());
                it = allServices.erase(it);
            } else {
                ++it;
            }
        }
        d->providerList.append(provider);
    }
    std::sort(d->providerList.begin(), d->providerList.end(),
              [](const Accounts::Provider &a, const Accounts::Provider &b) {
        return SailfishAccounts::translatedDisplayName(a).localeAwareCompare(SailfishAccounts::translatedDisplayName(b)) < 0;
    });
    d->filteredProviderList = d->providerList;
}

QHash<int, QByteArray> ProviderModel::roleNames() const
{
    Q_D(const ProviderModel);
    return d->headerData;
}

ProviderModel::~ProviderModel()
{
}

/*!
    \qmlproperty list ProviderModel::serviceFilter

    Controls the providers that are listed in the model. This is a list of strings of the services
    that must be supported by the listed providers.

    For example, if the serviceFilter is ["e-mail", "IM"], then the model will only include
    providers with "e-mail" or "IM" services. The service string comparison is case-insensitive.

    If the serviceFilter is an empty string, then all providers are included in the model regardless
    of their supported services. This is the default value.
 */

QStringList ProviderModel::serviceFilter() const
{
    Q_D(const ProviderModel);
    return d->serviceFilters;
}

void ProviderModel::setServiceFilter(const QStringList &serviceFilter)
{
    Q_D(ProviderModel);
    if (serviceFilter != d->serviceFilters) {
        d->serviceFilters = serviceFilter;
        d->reloadProviders();
        emit serviceFilterChanged();
    }
}

QStringList ProviderModel::providerFilter() const
{
    Q_D(const ProviderModel);
    return d->providerFilters;
}

void ProviderModel::setProviderFilter(const QStringList &providerFilter)
{
    Q_D(ProviderModel);
    if (providerFilter != d->providerFilters) {
        d->providerFilters = providerFilter;
        d->reloadProviders();
        emit providerFilterChanged();
    }
}

QStringList ProviderModel::otherExcludedProviders() const
{
    Q_D(const ProviderModel);
    return d->otherExcludedProviders;
}

void ProviderModel::setOtherExcludedProviders(const QStringList &otherExcludedProviders)
{
    Q_D(ProviderModel);
    if (otherExcludedProviders != d->otherExcludedProviders) {
        d->otherExcludedProviders = otherExcludedProviders;
        d->reloadProviders();
        emit otherExcludedProvidersChanged();
    }
}

bool ProviderModel::excludeProvidersForUncreatableAccounts() const
{
    Q_D(const ProviderModel);
    return d->excludeProvidersForUncreatableAccounts;
}

void ProviderModel::setExcludeProvidersForUncreatableAccounts(bool excludeProvidersForUncreatableAccounts)
{
    Q_D(ProviderModel);
    if (excludeProvidersForUncreatableAccounts != d->excludeProvidersForUncreatableAccounts) {
        d->excludeProvidersForUncreatableAccounts = excludeProvidersForUncreatableAccounts;
        d->reloadAccountCounts();
        d->reloadProviders();
        emit excludeProvidersForUncreatableAccountsChanged();
    }
}

QStringList ProviderModel::providerNames() const
{
    Q_D(const ProviderModel);
    return d->filteredProviderNames;
}

int ProviderModel::rowCount(const QModelIndex &) const
{
    Q_D(const ProviderModel);
    return d->filteredProviderList.count();
}

QVariant ProviderModel::data(const QModelIndex& index, int role) const
{
    Q_D(const ProviderModel);
    if (!index.isValid() || index.row() >= d->filteredProviderList.length())
        return QVariant();

    Accounts::Provider provider = d->filteredProviderList.at(index.row());
    if (!provider.isValid())
        return QVariant();

    const Role modelRole = static_cast<Role>(role);
    switch (modelRole) {
    case ProviderNameRole:
        return provider.name();
    case ProviderDisplayNameRole:
        return SailfishAccounts::translatedDisplayName(provider);
    case ProviderDescriptionRole:
        return d->retrieveDescription(provider);
    case ProviderIconRole:
        return provider.iconName();
    case ProviderIsSingleAccountRole:
        return provider.isSingleAccount();
    }

    return QVariant();
}

void ProviderModel::classBegin()
{
}

void ProviderModel::componentComplete()
{
    Q_D(ProviderModel);
    d->componentComplete = true;
    if (d->hasFilters()) {
        d->reloadProviders();
    }
}

Q_DECLARE_METATYPE(Accounts::Provider)

#include "providermodel.moc"
