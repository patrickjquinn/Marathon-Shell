// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation.
// SPDX-FileCopyrightText: 2013-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2013-2016 Canonical Ltd.
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

#include "account-service.h"
#include "manager.h"
#include "utils.h"
#include <QPointer>
#include <libaccounts-glib.h>

namespace Accounts
{

/*!
 * @class AccountService
 * @headerfile account-service.h Accounts/AccountService
 *
 * @brief Account settings for a specific service
 *
 * @details The AccountService class provides access to the account settings
 * for a specific service type. It is meant to be easier to use than the
 * Account class because it hides the complexity of the account structure and
 * gives access to only the limited subset of account settings which are
 * relevant to a service.
 *
 * To get an AccountService one can use the Manager methods accountServices()
 * or enabledAccountServices(), which both return a QList of account services.
 * Note that if the Manager was instantiated for a specific service type, these
 * lists will contain only those account services matching that service type.
 * The AccountService can also be instantiated with its AccountService(Account
 * *account, Service *service) constructor: this is useful if one already has
 * an Account instance.
 *
 * This is intended to be a convenient wrapper over the accounts settings
 * specific for a service; as such, it doesn't offer all the editing
 * possibilities offered by the Account class, such as enabling the service
 * itself: these operations should ideally not be performed by consumer
 * applications, but by the account editing UI only.
 *
 * Example code:
 * @code
 * // Instantiate an account manager interested in e-mail services only.
 * Accounts::Manager *manager = new Accounts::Manager("e-mail");
 *
 * // Get the list of enabled AccountService objects of type e-mail.
 * Accounts::AccountServiceList services = manager->enabledAccountServices();
 *
 * // Loop through the account services and do something useful with them.
 * foreach (Accounts::AccountService service, services) {
 *     QString server = service.value("pop3/hostname").toString();
 *     int port = service.value("pop3/port").toInt();
 *
 *     // Suppose that the e-mail address is stored in the global account
 *     // settings; let's get it from there:
 *     QString fromAddress = service.account()->valueAsString("username");
 *
 *     ...
 * }
 * @endcode
 *
 * @note User applications (with the notable exception of the accounts editing
 * application) should never use account services which are not enabled, and
 * should stop using an account when the account service becomes disabled. The
 * latter can be done by connecting to the changed() signal and checking if
 * isEnabled() still returns true.
 * @note Note that if the account gets deleted, it will always get disabled
 * first; so, there is no need to connect to the Account::removed() signal; one
 * can just monitor the changed() signal from the AccountService objects.
 */

/*!
 * @fn AccountService::enabled(bool isEnabled)
 *
 * Emitted when the enabledness state of the account service has changed.
 */


/*!
 * @fn AccountService::changed()
 * Emitted when some setting has changed on the account service.
 * You can use the changedFields() method to retrieve the list of the
 * settings which have changed.
 */

class AccountServicePrivate
{
    Q_DECLARE_PUBLIC(AccountService)

public:
    AccountServicePrivate(Account *account,
                          const Service &service,
                          AccountService *accountService);
    ~AccountServicePrivate();

private:
    static void onEnabled(AccountService *accountService, gboolean isEnabled);
    static void onChanged(AccountService *accountService);

    ServiceList m_serviceList;
    AgAccountService *m_accountService;
    QPointer<Account> m_account;
    QString prefix;
    mutable AccountService *q_ptr;
};

} // namespace

using namespace Accounts;

static QChar slash = QChar::fromLatin1('/');

AccountServicePrivate::AccountServicePrivate(Account *account,
                                             const Service &service,
                                             AccountService *accountService):
    m_account(account),
    q_ptr(accountService)
{
    m_accountService = ag_account_service_new(account->account(),
                                              service.service());
    g_signal_connect_swapped(m_accountService, "enabled",
                             G_CALLBACK(&onEnabled), accountService);
    g_signal_connect_swapped(m_accountService, "changed",
                             G_CALLBACK(&onChanged), accountService);
}

AccountServicePrivate::~AccountServicePrivate()
{
    Q_Q(AccountService);
    g_signal_handlers_disconnect_by_func(m_accountService,
                                         (void *)&onEnabled, q);
    g_signal_handlers_disconnect_by_func(m_accountService,
                                         (void *)&onChanged, q);
    g_object_unref(m_accountService);
    m_accountService = nullptr;
}

void AccountServicePrivate::onEnabled(AccountService *accountService,
                                      gboolean isEnabled)
{
    Q_EMIT accountService->enabled(isEnabled);
}

void AccountServicePrivate::onChanged(AccountService *accountService)
{
    Q_EMIT accountService->changed();
}

/*!
 * Constructor.
 * @param account An Account.
 * @param service A Service supported by the account.
 */
AccountService::AccountService(Account *account, const Service &service):
    QObject(nullptr),
    d_ptr(new AccountServicePrivate(account, service, this))
{
}

/*!
 * Constructor.
 * @param account An Account.
 * @param service A Service supported by the account.
 * @param parent The parent object.
 */
AccountService::AccountService(Account *account, const Service &service,
                               QObject *parent):
    QObject(parent),
    d_ptr(new AccountServicePrivate(account, service, this))
{
}

/*!
 * Destructor.
 */
AccountService::~AccountService()
{
    delete d_ptr;
}

/*!
 * Return the Account. Do not delete this object explicitly.
 */
Account *AccountService::account() const
{
    Q_D(const AccountService);
    return d->m_account;
}

/*!
 * Return the Service.
 */
Service AccountService::service() const
{
    Q_D(const AccountService);
    AgService *service = ag_account_service_get_service(d->m_accountService);
    return Service(service);
}

/*!
 * Check whether the account service is enabled.
 * @note this is just a wrapper of isEnabled
 * @see isEnabled()
 * @deprecated use isEnabled instead
 */
bool AccountService::enabled() const
{
    return isEnabled();
}

/*!
 * Check whether the account service is enabled.
 */
bool AccountService::isEnabled() const
{
    Q_D(const AccountService);
    return ag_account_service_get_enabled(d->m_accountService);
}

/*!
 * Return all the keys in the current group.
 */
QStringList AccountService::allKeys() const
{
    Q_D(const AccountService);
    QStringList allKeys;
    AgAccountSettingIter iter;
    const gchar *key;
    GVariant *val;

    /* iterate the settings */
    QByteArray tmp = d->prefix.toLatin1();
    ag_account_service_settings_iter_init(d->m_accountService,
                                          &iter, tmp.constData());
    while (ag_account_settings_iter_get_next(&iter, &key, &val))
    {
        allKeys.append(ASCII(key));
    }
    return allKeys;
}

/*!
 * Enter a group. This method never fails.
 * @param prefix
 */
void AccountService::beginGroup(const QString &prefix)
{
    Q_D(AccountService);
    d->prefix += prefix + slash;
}

/*!
 * Return all the groups which are direct children of the current group.
 */
QStringList AccountService::childGroups() const
{
    QStringList groups, all_keys;

    all_keys = allKeys();
    Q_FOREACH (const QString &key, all_keys)
    {
        if (key.contains(slash)) {
            QString group = key.section(slash, 0, 0);
            if (!groups.contains(group))
                groups.append(group);
        }
    }
    return groups;
}

/*!
 * Return all the keys which are direct children of the current group.
 */
QStringList AccountService::childKeys() const
{
    QStringList keys, all_keys;

    all_keys = allKeys();
    Q_FOREACH (const QString &key, all_keys)
    {
        if (!key.contains(slash))
            keys.append(key);
    }
    return keys;
}

/*!
 * Remove all the keys.
 * @see remove(const QString &key)
 */
void AccountService::clear()
{
    Q_D(AccountService);
    /* clear() must ignore the group: so, temporarily reset it and call
     * remove("") */
    QString saved_prefix = d->prefix;
    d->prefix = QString();
    remove(QString());
    d->prefix = saved_prefix;
}

/*!
 * Check whether the given key is in the current group.
 * @param key The key name of the setting.
 */
bool AccountService::contains(const QString &key) const
{
    return childKeys().contains(key);
}

/*!
 * Exit a group.
 */
void AccountService::endGroup()
{
    Q_D(AccountService);
    d->prefix = d->prefix.section(slash, 0, -3,
                                  QString::SectionIncludeTrailingSep);
    if (!d->prefix.isEmpty() && d->prefix[0] == slash) d->prefix.remove(0, 1);
}

/*!
 * Return the name of the current group.
 */
QString AccountService::group() const
{
    Q_D(const AccountService);
    if (d->prefix.endsWith(slash))
        return d->prefix.left(d->prefix.size() - 1);
    return d->prefix;
}

/*!
 * Remove the given key. If the key is the empty string, all keys in the
 * current group are removed.
 * @param key The key name of the setting.
 */
void AccountService::remove(const QString &key)
{
    Q_D(AccountService);
    if (key.isEmpty())
    {
        /* delete all keys in the group */
        QStringList keys = allKeys();
        Q_FOREACH (const QString &key, keys)
        {
            if (!key.isEmpty())
                remove(key);
        }
    }
    else
    {
        QString full_key = d->prefix + key;
        QByteArray tmpkey = full_key.toLatin1();
        ag_account_service_set_variant(d->m_accountService,
                                       tmpkey.constData(),
                                       NULL);
    }
}

/*!
 * Change the value of an account setting.
 * @param key The name of the setting.
 * @param value The new value of the setting.
 */
void AccountService::setValue(const QString &key, const QVariant &value)
{
    Q_D(AccountService);

    GVariant *variant = qVariantToGVariant(value);
    if (variant == nullptr) {
        return;
    }

    QString full_key = d->prefix + key;
    QByteArray tmpkey = full_key.toLatin1();
    ag_account_service_set_variant(d->m_accountService,
                                   tmpkey.constData(),
                                   variant);
}

void AccountService::setValue(const char *key, const QVariant &value)
{
    setValue(ASCII(key), value);
}

/*!
 * Retrieves the value of an account setting, as a QVariant.
 * @param key The key whose value must be retrieved.
 * @param defaultValue Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * @return The value associated to \a key.
 *
 * This method operates on the currently selected service.
 */
QVariant AccountService::value(const QString &key,
                               const QVariant &defaultValue,
                               SettingSource *source) const
{
    Q_D(const AccountService);
    QString full_key = d->prefix + key;
    QByteArray ba = full_key.toLatin1();
    AgSettingSource settingSource;
    GVariant *variant =
        ag_account_service_get_variant(d->m_accountService,
                                       ba.constData(),
                                       &settingSource);
    if (source != nullptr) {
        switch (settingSource) {
        case AG_SETTING_SOURCE_ACCOUNT: *source = ACCOUNT; break;
        case AG_SETTING_SOURCE_PROFILE: *source = TEMPLATE; break;
        default: *source = NONE; break;
        }
    }

    return (variant != nullptr) ? gVariantToQVariant(variant) : defaultValue;
}

/*!
 * Retrieves the value of an account setting.
 * @param key The key whose value must be retrieved
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * Returns the value of the setting, or an invalid QVariant if unset.
 */
QVariant AccountService::value(const QString &key, SettingSource *source) const
{
    return value(key, QVariant(), source);
}

QVariant AccountService::value(const char *key, SettingSource *source) const
{
    return value(ASCII(key), source);
}

/*!
 * This method should be called only in the context of a handler of the
 * AccountService::changed() signal, and can be used to retrieve the set of
 * changes.
 *
 * @return a QStringList of the keys which have changed.
 */
QStringList AccountService::changedFields() const
{
    Q_D(const AccountService);

    gchar **changedFields =
        ag_account_service_get_changed_fields(d->m_accountService);

    QStringList keyList;
    if (changedFields == nullptr)
        return keyList;

    gchar **keys = changedFields;
    while (*keys != nullptr) {
        keyList.append(QString(ASCII(*keys)));
        keys++;
    }

    g_strfreev(changedFields);
    return keyList;
}

/*!
 * Read the authentication data stored in the account (merging the
 * service-specific settings with the global account settings).
 * The method and mechanism are read from the "auth/method" and
 * "auth/mechanism" keys, respectively. The authentication parameters are
 * found under the "auth/<method>/<mechanism>/" group.
 *
 * @return an AuthData object, describing the authentication settings.
 */
AuthData AccountService::authData() const
{
    Q_D(const AccountService);

    AgAuthData *agAuthData =
        ag_account_service_get_auth_data(d->m_accountService);
    AuthData authData(agAuthData);
    ag_auth_data_unref(agAuthData);
    return authData;
}
