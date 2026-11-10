// SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "servicemodel.h"
#include "service.h"
#include "globalaccountmanager_p.h"
#include "globaltranslatorcache_p.h"

#include <QDebug>
#include <QHash>

// libaccounts-qt
#include <Accounts/Manager>

class ServiceModel::ServiceModelPrivate
{
public:
    ServiceModelPrivate()
        : componentComplete(false)
    {
    }

    ~ServiceModelPrivate() {}

    void applyServiceTypeFilter()
    {
        QList<Accounts::Service> result;
        foreach (const Accounts::Service &service, serviceList) {
            if (service.serviceType() == serviceTypeFilter) {
                result.append(service);
            }
        }
        filteredServiceList = result;
    }

    QList<Accounts::Service> serviceList;
    QList<Accounts::Service> filteredServiceList;
    QHash<QString, QStringList> providerServiceTypes;
    QHash<int, QByteArray> roleNames;
    QString serviceTypeFilter;
    bool componentComplete;
};

/*!
    \qmltype ServiceModel
    \instantiates ServiceModel
    \inherits QAbstractListModel
    \inqmlmodule Sailfish.Accounts 1
    \brief Provides a model of existing account provider services

    The ServiceModel can be used to provide a model of account provider services.

    The following roles are exposed for each service:

    \list
    \li \c serviceName
    \li \c serviceDisplayName
    \li \c serviceIcon
    \endlist
*/

ServiceModel::ServiceModel(QObject* parent)
    : QAbstractListModel(parent)
    , d_ptr(new ServiceModelPrivate)
{
    Q_D(ServiceModel);

    d->roleNames.insert(ServiceNameRole, "serviceName");
    d->roleNames.insert(ServiceDisplayNameRole, "serviceDisplayName");
    d->roleNames.insert(ServiceIconRole, "serviceIcon");
    d->roleNames.insert(ServiceTypeRole, "serviceType");
    d->roleNames.insert(ServiceTagsRole, "serviceTags");
    d->roleNames.insert(ServiceProviderNameRole, "serviceProviderName");

    Accounts::Manager *m = globalAccountManager();
//    Accounts::ServiceList allServices = m->serviceList(); // force reload of service files.
    d->serviceList = m->serviceList(); // force reload of service files.
    d->filteredServiceList = d->serviceList;
}

QHash<int, QByteArray> ServiceModel::roleNames() const
{
    Q_D(const ServiceModel);
    return d->roleNames;
}

ServiceModel::~ServiceModel()
{
    Q_D(ServiceModel);
    delete d;
}

/*!
    \qmlproperty string ServiceModel::serviceTypeFilter

    If set, the model will only contain services with the specified service type.
 */

QString ServiceModel::serviceTypeFilter() const
{
    Q_D(const ServiceModel);
    return d->serviceTypeFilter;
}

void ServiceModel::setServiceTypeFilter(const QString &serviceTypeFilter)
{
    Q_D(ServiceModel);
    if (serviceTypeFilter != d->serviceTypeFilter) {
        d->serviceTypeFilter = serviceTypeFilter;
        if (d->componentComplete) {
            beginResetModel();
            d->applyServiceTypeFilter();
            endResetModel();
        }
        emit serviceTypeFilterChanged();
    }
}

int ServiceModel::rowCount(const QModelIndex &) const
{
    Q_D(const ServiceModel);
    return d->filteredServiceList.count();
}

QVariant ServiceModel::data(const QModelIndex& index, int role) const
{
    Q_D(const ServiceModel);
    if (!index.isValid() || index.row() >= d->filteredServiceList.length())
        return QVariant();

    Accounts::Service service = d->filteredServiceList.at(index.row());
    if (!service.isValid())
        return QVariant();

    switch (role) {
    case ServiceNameRole:
        return service.name();
    case ServiceDisplayNameRole:
        return SailfishAccounts::translatedDisplayName(service);
    case ServiceIconRole:
        return service.iconName();
    case ServiceTypeRole:
        return service.serviceType();
    case ServiceTagsRole:
        return QVariant::fromValue(service.tags().values()); // Modified by Shipwright for Qt 6: QSet::values()
    case ServiceProviderNameRole:
        return service.provider();
    }
    return QVariant();
}

void ServiceModel::classBegin()
{
}

void ServiceModel::componentComplete()
{
    Q_D(ServiceModel);
    if (!d->serviceTypeFilter.isEmpty()) {
        beginResetModel();
        d->applyServiceTypeFilter();
        endResetModel();
    }
    d->componentComplete = true;
}
