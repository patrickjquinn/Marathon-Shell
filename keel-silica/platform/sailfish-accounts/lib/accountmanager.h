/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTMANAGER_H
#define SAILFISH_ACCOUNTS__ACCOUNTMANAGER_H

#include <QtCore/QObject>

#include <QtGlobal>
#include <QtQml>
#include <QQmlParserStatus>

#include <QtCore/QStringList>
#include <QtCore/QString>

class AccountManagerPrivate;
class ServiceType;
class Provider;
class Service;
class Account;

namespace Accounts {
class Provider;
class Service;
class ServiceType;
}

class Q_DECL_EXPORT AccountManager : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(QStringList serviceTypeNames READ serviceTypeNames NOTIFY serviceTypeNamesChanged)
    Q_PROPERTY(QStringList providerNames READ providerNames NOTIFY providerNamesChanged)
    Q_PROPERTY(QStringList serviceNames READ serviceNames NOTIFY serviceNamesChanged)
    Q_PROPERTY(QList<int> accountIdentifiers READ accountIdentifiers NOTIFY accountIdentifiersChanged)

public:
    AccountManager(QObject *parent = 0);
    ~AccountManager();

    // invokable api.
    Q_INVOKABLE QList<int> providerAccountIdentifiers(const QString &providerName);
    Q_INVOKABLE bool createAccount(const QString &providerName);

    Q_INVOKABLE ServiceType *serviceType(const QString &serviceTypeName) const;
    Q_INVOKABLE Service *service(const QString &serviceName) const;
    Q_INVOKABLE Provider *provider(const QString &providerName) const;
    Q_INVOKABLE Provider *providerForAccount(int accountId) const;
    Q_INVOKABLE Account *account(int accountId) const;
    Q_INVOKABLE bool credentialsNeedUpdate(int accountId);
    Q_INVOKABLE QList<int> enabledAccounts(const QString &providerName, const QString &serviceName);

    // property accessors and mutators.
    QStringList serviceTypeNames() const;
    QStringList providerNames() const;
    QStringList serviceNames() const;
    QList<int> accountIdentifiers() const;

    void classBegin();
    void componentComplete();

    // Provided for external use
    // Internally globaltranslatorcache_p.h should be used instead
    static QString translatedDisplayName(const Accounts::Provider &instance);
    static QString translatedDisplayName(const Accounts::Service &instance);
    static QString translatedDisplayName(const Accounts::ServiceType &instance);

Q_SIGNALS:
    void serviceTypeNamesChanged();
    void providerNamesChanged();
    void serviceNamesChanged();
    void accountIdentifiersChanged();

    void accountCreated(int accountId, const QString &providerName);
    void accountCreationFailed(const QString &message, const QString &providerName);

private:
    AccountManagerPrivate *d;
    friend class AccountManagerPrivate;
};

#endif
