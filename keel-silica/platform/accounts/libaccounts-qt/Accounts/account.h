// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2011 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */
/*!
 * @copyright Copyright (C) 2009-2011 Nokia Corporation.
 * @license LGPL
 */

#ifndef ACCOUNTS_ACCOUNT_H
#define ACCOUNTS_ACCOUNT_H

#include "Accounts/accountscommon.h"
#include "Accounts/error.h"
#include "Accounts/service.h"

#define ACCOUNTS_KEY_CREDENTIALS_ID QStringLiteral("CredentialsId")
#include <QObject>
#include <QStringList>
#include <QVariant>

extern "C"
{
    typedef struct _AgAccount AgAccount;
    typedef struct _AgAccountWatch *AgAccountWatch;
}

/*!
 * @namespace Accounts
 */

namespace Accounts
{
typedef quint32 AccountId;
typedef QList<AccountId> AccountIdList;
class Manager;
class Provider;
class AccountServicePrivate;

/*!
 * Tells the origin of an account setting: whether it was set on the account,
 * or is it a default value in the service template, or whether it is unset.
 */
enum SettingSource
{
    NONE,
    ACCOUNT,
    TEMPLATE
};

class ACCOUNTS_EXPORT Watch: public QObject
{
    Q_OBJECT

public:
    /* We don't want to document these.
     * \cond
     */
    Watch(QObject *parent = nullptr);
    ~Watch();

    void setWatch(AgAccountWatch w) { watch = w; };
    class Private;
    // \endcond

Q_SIGNALS:
    void notify(const char *key);

    // \cond
private:
    AgAccountWatch watch;
    friend class Private;
    // \endcond
};

class ACCOUNTS_EXPORT Account: public QObject
{
    Q_OBJECT

public:
    Account(Manager *manager, const QString &provider, QObject *parent = nullptr);
    virtual ~Account();

    static Account *fromId(Manager *manager, AccountId id,
                           QObject *parent = nullptr);

    AccountId id() const;

    Manager *manager() const;

    bool supportsService(const QString &serviceType) const;

    ServiceList services(const QString &serviceType = QString()) const;
    ServiceList enabledServices() const;

    bool enabled() const;
    bool isEnabled() const;
    void setEnabled(bool);

    /*!
     * Gets the account's credentials ID in Signon database.
     *
     * The credentials ID is first read from the currently selected service;
     * if it is not found, then it is ready from the global account settings.
     * In any case, the currently selected service is not altered.
     */
    uint credentialsId();

    /*!
     * Sets the accounts credentials ID.
     * The change will be written only when sync() is called.
     *
     * This method operates on the currently selected service.
     */
    void setCredentialsId(const uint id) {
        setValue(ACCOUNTS_KEY_CREDENTIALS_ID, id);
    }

    QString displayName() const;
    void setDisplayName(const QString &displayName);

    QString providerName() const;
    Provider provider() const;

    void selectService(const Service &service = Service());
    Service selectedService() const;

    /* QSettings-like methods */
    QStringList allKeys() const;
    void beginGroup(const QString &prefix);
    QStringList childGroups() const;
    QStringList childKeys() const;
    void clear();
    bool contains(const QString &key) const;
    void endGroup();
    QString group() const;
    bool isWritable() const;
    void remove(const QString &key);

    void setValue(const QString &key, const QVariant &value);
    QVariant value(const QString &key,
                   const QVariant &defaultValue = QVariant(),
                   SettingSource *source = nullptr) const;
    SettingSource value(const QString &key, QVariant &value) const;
    QString valueAsString(const QString &key,
                          QString default_value = QString(),
                          SettingSource *source = nullptr) const;
    int valueAsInt(const QString &key,
                   int default_value = 0,
                   SettingSource *source = nullptr) const;
    quint64 valueAsUInt64(const QString &key,
                   quint64 default_value = 0,
                   SettingSource *source = nullptr) const;
    bool valueAsBool(const QString &key,
                     bool default_value = false,
                     SettingSource *source = nullptr) const;

    Watch *watchKey(const QString &key = QString());

    void sync();
    bool syncAndBlock();

    void remove();

    void sign(const QString &key, const char *token);
    bool verify(const QString &key, const char **token);
    bool verifyWithTokens(const QString &key, QList<const char*> tokens);

Q_SIGNALS:
    void displayNameChanged(const QString &displayName);
    void enabledChanged(const QString &serviceName, bool enabled);

    void error(Accounts::Error error);
    void synced();

    void removed();

private:
    AgAccount *account();
    // Don't include private data in docs: \cond
    class Private;
    Account(Private *d, QObject *parent = nullptr);
    friend class Manager;
    friend class Account::Private;
    friend class Watch;
    friend class AccountService;
    friend class AccountServicePrivate;

    Private *d;
    // \endcond
};


} //namespace Accounts

#endif // ACCOUNTS_ACCOUNT_H
