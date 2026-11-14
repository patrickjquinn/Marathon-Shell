/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__PROVIDERMODEL_H
#define SAILFISH_ACCOUNTS__PROVIDERMODEL_H

//Qt
#include <QAbstractListModel>
#include <QQmlParserStatus>
#include <QStringList>

/*
  Filter options:
  - serviceFilter: Only include providers with these services
  - providerFilter: Only include providers with these names
  - excludeProvidersForUncreatableAccounts: if ProviderIsSingleAccount=true and an account exists, exclude the provider
  - otherExcludedProviders: Additionally exclude providers with these names

  Providers must match all conditions to be included in the model.
*/

class Q_DECL_EXPORT ProviderModel : public QAbstractListModel, public QQmlParserStatus
{
    Q_OBJECT
    class ProviderModelPrivate;
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(int count READ rowCount NOTIFY rowCountChanged)
    Q_PROPERTY(QStringList providerNames READ providerNames NOTIFY providerNamesChanged)

    Q_PROPERTY(QStringList serviceFilter READ serviceFilter WRITE setServiceFilter NOTIFY serviceFilterChanged)
    Q_PROPERTY(QStringList providerFilter READ providerFilter WRITE setProviderFilter NOTIFY providerFilterChanged)
    Q_PROPERTY(bool excludeProvidersForUncreatableAccounts READ excludeProvidersForUncreatableAccounts WRITE setExcludeProvidersForUncreatableAccounts NOTIFY excludeProvidersForUncreatableAccountsChanged)
    Q_PROPERTY(QStringList otherExcludedProviders READ otherExcludedProviders WRITE setOtherExcludedProviders NOTIFY otherExcludedProvidersChanged)

public:
    enum Role {
        ProviderNameRole = Qt::UserRole + 1,
        ProviderDisplayNameRole,
        ProviderDescriptionRole,
        ProviderIconRole,
        ProviderIsSingleAccountRole
    };

    ProviderModel(QObject* parent = 0);
    ~ProviderModel();

    QStringList serviceFilter() const;
    void setServiceFilter(const QStringList &serviceFilter);

    QStringList providerFilter() const;
    void setProviderFilter(const QStringList &providerFilter);

    QStringList otherExcludedProviders() const;
    void setOtherExcludedProviders(const QStringList &otherExcludedProviders);

    bool excludeProvidersForUncreatableAccounts() const;
    void setExcludeProvidersForUncreatableAccounts(bool excludeProvidersForUncreatableAccounts);

    QStringList providerNames() const;

    int rowCount( const QModelIndex & index = QModelIndex() ) const override;
    QVariant data( const QModelIndex &index, int role ) const override;

    void classBegin() override;
    void componentComplete() override;

Q_SIGNALS:
    void rowCountChanged();
    void providerNamesChanged();
    void serviceFilterChanged();
    void providerFilterChanged();
    void otherExcludedProvidersChanged();
    void excludeProvidersForUncreatableAccountsChanged();

protected:
    QHash<int, QByteArray> roleNames() const;

private:
    ProviderModelPrivate* d_ptr;
    Q_DISABLE_COPY(ProviderModel)
    Q_DECLARE_PRIVATE(ProviderModel)
};

#endif
