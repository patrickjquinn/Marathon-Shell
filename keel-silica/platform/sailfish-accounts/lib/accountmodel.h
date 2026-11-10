/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTMODEL_H
#define SAILFISH_ACCOUNTS__ACCOUNTMODEL_H

// accounts-qt
#include <Accounts/Manager>

#include <QQmlParserStatus>
#include <QAbstractTableModel>
#include <QMap>
#include <QVariant>

class Provider;
class Account;

/*!
 * The Account Model is the model for created accounts
 */

class Q_DECL_EXPORT AccountModel : public QAbstractListModel, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(FilterType filterType READ filterType WRITE setFilterType NOTIFY filterTypeChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(bool filterByEnabled READ filterByEnabled WRITE setFilterByEnabled NOTIFY filterByEnabledChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_ENUMS(FilterType)
    Q_ENUMS(AccountError)
    class AccountModelPrivate;

public:
    enum Roles {
        AccountIdRole = Qt::UserRole + 1,
        AccountDisplayNameRole,
        AccountIconRole,
        ProviderNameRole,
        ProviderDisplayNameRole,
        ProviderValidRole,
        AccountEnabledRole,
        AccountErrorRole,
        PerformingInitialSyncRole,
        AccountUserNameRole,
        AccountReadOnlyRole,
        AccountProvisionedRole,
        AccountLimitedRole
    };

    enum FilterType {
        NoFilter,
        ProviderFilter,
        ServiceFilter,
        ServiceTypeFilter,
        ProvisionedFilter
    };

    enum AccountError {
        NoAccountError,
        AccountNotSignedInError,
        UnknownAccountError = 100
    };

    AccountModel(QObject *parent = 0);
    virtual ~AccountModel();

    FilterType filterType() const;
    void setFilterType(FilterType filterType);

    QString filter() const;
    void setFilter(const QString &filter);

    bool filterByEnabled() const;
    void setFilterByEnabled(bool filterByEnabled);

    int count() const;

    Q_INVOKABLE void setAccountEnabled(int index, bool enabled);
    Q_INVOKABLE QVariantMap getByAccount(int accountId);
    Q_INVOKABLE QVariantMap get(int index);
    Q_INVOKABLE bool accountHasServiceOfTypeEnabled(int accountId, const QString &serviceTypeName);

    int rowCount(const QModelIndex &index = QModelIndex()) const;
    QVariant data(const QModelIndex &index, int role) const;

    void classBegin();
    void componentComplete();

signals:
    void filterTypeChanged();
    void filterChanged();
    void filterByEnabledChanged();
    void countChanged();

protected:
    QHash<int, QByteArray> roleNames() const;

private slots:
    void accountCreated(Accounts::AccountId id);
    void accountRemoved(Accounts::AccountId id);
    void accountUpdated(Accounts::AccountId id);
    void accountDisplayNameChanged();
    void accountEnabledChanged();
    void delayedIndexUpdate();
    void exchangeSyncStarted(qulonglong accountId);
    void exchangeSyncCompleted(qulonglong accountId, int result);
    void profileSyncStatusChanged(const QString &profileId, int status, const QString &errorString);

private:
    int getAccountIndex(Accounts::AccountId id) const;
    int getFilteredAccountsIndex(Accounts::AccountId id) const;
    void addedAccount(Accounts::Account *account);
    void removedAccount(Accounts::Account *account);
    void populate();
    void reload(bool emitCountChange = true);
    void monitorSyncStatus(Accounts::Account *account);

private:
    friend class DisplayData;

    AccountModelPrivate* d_ptr;
    Q_DISABLE_COPY(AccountModel)
    Q_DECLARE_PRIVATE(AccountModel)
};
Q_DECLARE_METATYPE(Accounts::Account *)

#endif
