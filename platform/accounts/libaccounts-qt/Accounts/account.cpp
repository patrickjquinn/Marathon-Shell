// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
// Modified by Shipwright for Qt 6: QVariant::type(), convert(int) and QVariant(Type) are deprecated; typeId(), metaType() and QMetaType.
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

#include "account.h"
#include "manager.h"
#include "manager_p.h"
#include "utils.h"

#include <QPointer>
#include <libaccounts-glib.h>

namespace Accounts {

/*!
 * @class Watch
 * @headerfile account.h Accounts/Account
 *
 * @brief Monitors an account key or group of keys.
 *
 * @details A watch is created via the Account::watch method and is a simple
 * object which will emit the notify() signal when the value of the key (or
 * group) that it is monitoring is changed.
 */

/*!
 * @class Account
 * @headerfile account.h Accounts/Account
 *
 * @brief The Account class provides an interface to account settings.
 *
 * @details The Account class is used to access the account and service settings.
 * This class has no constructor, therefore to instantiate one Account object
 * one has to either use the Manager::createAccount method (to create a new
 * empty account) or Manager::account (to load an existing account).
 *
 * @attention Do not call setParent() on an account object; the Account class
 * assumes that the parent is always the Manager, and changing it will have
 * unpredictable results.
 *
 * Most of the methods in the Account class act on the selected service: for
 * example, calling setEnabled(false) on the NULL service (this is the service
 * to be used for changing settings globally on the account) will disable the
 * account, while the code
 * \code
 * account->selectService(myService);
 * account->setEnabled(false);
 * \endcode
 * will disable the "myService" service.
 *
 * All changes made on an account (including deletion) are not stored until
 * sync() is called.
 */

class Account::Private
{
public:
    Private(Manager *manager, const QString &providerName, Account *account);
    Private(Manager *manager, AgAccount *agAccount);

    ~Private()
    {
        g_cancellable_cancel(m_cancellable);
        g_object_unref(m_cancellable);
        m_cancellable = NULL;
    }

    void init(Account *account);

    QPointer<Manager> m_manager;
    AgAccount *m_account;  //real account
    GCancellable *m_cancellable;
    QString prefix;

    static void on_display_name_changed(Account *self);
    static void on_enabled(Account *self, const gchar *service_name,
                           gboolean enabled);
    static void account_store_cb(AgAccount *account,
                                 GAsyncResult *res,
                                 Account *self);
    static void on_deleted(Account *self);
};

class Watch::Private
{
public:
    static void account_notify_cb(AgAccount *account, const gchar *key,
                                  Watch *self);
};
} //namespace Accounts


using namespace Accounts;

static QChar slash = QChar::fromLatin1('/');

/*!
 * @fn Watch::notify(const char *key)
 *
 * Emitted when the value of the keys monitored by this watch change.
 * @param key The string that was used to create this watch. Note that if
 * this watch is monitor multiple keys this param only identifies their
 * common prefix, and not the actual key being changed.
 */

Watch::Watch(QObject *parent):
    QObject(parent)
{
}

Watch::~Watch()
{
    Account *account = qobject_cast<Account *>(QObject::parent());
    /* The destructor of Account deletes the child Watches before detaching
     * them, so here account should always be not NULL */
    Q_ASSERT(account != NULL);
    ag_account_remove_watch(account->d->m_account, watch);
}

Account::Private::Private(Manager *manager, const QString &providerName,
                          Account *account):
    m_manager(manager),
    m_cancellable(g_cancellable_new())
{
    m_account = ag_manager_create_account(manager->d->m_manager,
                                          providerName.toUtf8().constData());
    init(account);
}

Account::Private::Private(Manager *manager, AgAccount *agAccount):
    m_manager(manager),
    m_account(agAccount),
    m_cancellable(g_cancellable_new())
{
}

void Account::Private::init(Account *account)
{
    if (m_account == nullptr) return;
    g_signal_connect_swapped(m_account, "display-name-changed",
                             G_CALLBACK(&Private::on_display_name_changed),
                             account);
    g_signal_connect_swapped(m_account, "enabled",
                             G_CALLBACK(&Private::on_enabled), account);
    g_signal_connect_swapped(m_account, "deleted",
                             G_CALLBACK(&Private::on_deleted), account);
}

void Account::Private::on_display_name_changed(Account *self)
{
    const gchar *name = ag_account_get_display_name(self->d->m_account);

    Q_EMIT self->displayNameChanged(UTF8(name));
}

void Account::Private::on_enabled(Account *self, const gchar *service_name,
                                  gboolean enabled)
{
    Q_EMIT self->enabledChanged(UTF8(service_name), enabled);
}

void Account::Private::on_deleted(Account *self)
{
    Q_EMIT self->removed();
}

/*!
 * @fn Account::error(Accounts::Error error)
 *
 * Emitted when an error occurs.
 */

/*!
 * Constructs a new Account. The account exists only in memory and is not
 * visible to other applications (or Manager instances) until sync() has been
 * called.
 * @param manager The account manager. Do not destroy it while the account
 * object is in use.
 * @param providerName Name of the provider for the account.
 * @param parent Parent object.
 */
Account::Account(Manager *manager, const QString &providerName,
                 QObject *parent):
    QObject(parent),
    d(new Private(manager, providerName, this))
{
}

Account::Account(Private *d, QObject *parent):
    QObject(parent),
    d(d)
{
    d->init(this);
}

/*!
 * Constructs an Account object representing an account stored in the database.
 * @param manager The account manager. Do not destroy it while the account
 * object is in use.
 * @param id The numeric identifier of the account.
 * @param parent Parent object.
 *
 * @return A new account object, or 0 if an error occurred.
 */
Account *Account::fromId(Manager *manager, AccountId id, QObject *parent)
{
    GError *error = nullptr;
    AgAccount *account = ag_manager_load_account(manager->d->m_manager, id,
                                                 &error);
    if (account == nullptr) {
        Q_ASSERT(error != nullptr);
        manager->d->lastError = Error(error);
        g_error_free(error);
        return 0;
    }
    Q_ASSERT(error == nullptr);
    return new Account(new Private(manager, account), parent);
}

/*!
 * Destroys the current account object and free all resources.
 */
Account::~Account()
{
    QObjectList list = children();
    for (int i = 0; i < list.count(); i++)
    {
        QObject *o = list.at(i);
        if (qobject_cast<Watch *>(o))
            delete o;
    }

    g_signal_handlers_disconnect_by_func
        (d->m_account, (void *)&Private::on_display_name_changed, this);
    g_signal_handlers_disconnect_by_func
        (d->m_account, (void *)&Private::on_enabled, this);
    g_signal_handlers_disconnect_by_func
        (d->m_account, (void *)&Private::on_deleted, this);
    g_object_unref(d->m_account);
    delete d;
    d = nullptr;
}

/*!
 * Returns the AccountId of this account (0 if the account has not yet been
 * stored into the database).
 */
AccountId Account::id() const
{
    return d->m_account ? d->m_account->id : 0;
}

/*!
 * Returns the Manager.
 */
Manager *Account::manager() const
{
    return d->m_manager;
}

/*!
 * Checks whether the account supports the given service.
 */
bool Account::supportsService(const QString &serviceType) const
{
    return ag_account_supports_service(d->m_account,
                                       serviceType.toUtf8().constData());
}

/*!
 * Returns a list of services supported by this account. If the manager was
 * constructed with given service type only the services which supports the
 * service type will be returned.
 *
 * This is currently computed by returning all services having the same
 * provider as the account.
 */
ServiceList Account::services(const QString &serviceType) const
{
    GList *list;
    if (serviceType.isEmpty()) {
        list = ag_account_list_services(d->m_account);
    } else {
        list = ag_account_list_services_by_type(d->m_account,
            serviceType.toUtf8().constData());
    }

    /* convert glist -> ServiceList */
    ServiceList servList;
    GList *iter;
    for (iter = list; iter; iter = iter->next)
    {
        AgService *service = (AgService*)iter->data;
        servList.append(Service(service, StealReference));
    }

    g_list_free(list);

    return servList;
}

/*!
 * Returns a list of enabled services supported by this account. If the manager
 * was constructed with given service type only the services which supports the
 * service type will be returned.
 */
ServiceList Account::enabledServices() const
{
    GList *list;
    list = ag_account_list_enabled_services(d->m_account);

    /* convert glist -> ServiceList */
    ServiceList servList;
    GList *iter;
    for (iter = list; iter; iter = g_list_next(iter))
    {
        AgService *service = (AgService*)iter->data;
        servList.append(Service(service, StealReference));
    }

    g_list_free(list);

    return servList;
}

/*!
 * Checks whether the account or selected service is enabled.
 *
 * This method operates on the currently selected service or
 * globally, if none selected.
 *
 * @note this is just a wrapper of isEnabled
 * @see isEnabled()
 * @deprecated use isEnabled instead
 */
bool Account::enabled() const
{
    return isEnabled();
}

/*!
 * Checks whether the account or selected service is enabled.
 *
 * This method operates on the currently selected service or
 * globally, if none selected.
 */
bool Account::isEnabled() const
{
    return ag_account_get_enabled(d->m_account);
}

/*!
 * Enables/disables the account or selected service.
 * The change will be written only when sync() is called.
 *
 * This method operates on the currently selected service or
 * globally, if none selected.
 */
void Account::setEnabled(bool enabled)
{
    ag_account_set_enabled(d->m_account, enabled);
}

/*!
 * Returns the display name of the account.
 *
 * This method operates on the currently selected service.
 */
QString Account::displayName() const
{
    return UTF8(ag_account_get_display_name(d->m_account));
}

/*!
 * Changes the display name of the account.
 * The change will be written only when sync() is called.
 */
void Account::setDisplayName(const QString &displayName)
{
    ag_account_set_display_name(d->m_account,
                                displayName.toUtf8().constData());
}

/*!
 * Returns the name of the provider of the account.
 */
QString Account::providerName() const
{
    return UTF8(ag_account_get_provider_name(d->m_account));
}

/*!
 * Returns the provider of the account.
 */
Provider Account::provider() const
{
    return manager()->provider(providerName());
}

/*!
 * Select the Service for the subsequent operations.
 * @param service The Service to select. If this is invalid, the global
 * account settings will be selected.
 */
void Account::selectService(const Service &service)
{
    AgService *agService = NULL;

    if (service.isValid())
        agService = service.service();

    ag_account_select_service(d->m_account, agService);
    d->prefix = QString();
}

/*!
 * @return The currently selected service.
 */
Service Account::selectedService() const
{
    AgService *agService = ag_account_get_selected_service(d->m_account);
    return Service(agService);
}

/*!
 * Returns all keys in the current group.
 *
 * This method operates on the currently selected service.
 */
QStringList Account::allKeys() const
{
    QStringList allKeys;
    AgAccountSettingIter iter;
    const gchar *key;
    GVariant *val;

    /* iterate the settings */
    QByteArray tmp = d->prefix.toLatin1();
    ag_account_settings_iter_init(d->m_account, &iter, tmp.constData());
    while (ag_account_settings_iter_get_next(&iter, &key, &val))
    {
        allKeys.append(QString(ASCII(key)));
    }
    return allKeys;
}

/*!
 * Enters a group. This method never fails.
 * @param prefix
 *
 * This method operates on the currently selected service.
 */
void Account::beginGroup(const QString &prefix)
{
    d->prefix += prefix + slash;
}

/*!
 * Returns all the groups which are direct children of the current group.
 *
 * This method operates on the currently selected service.
 */
QStringList Account::childGroups() const
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
 *
 * This method operates on the currently selected service.
 */
QStringList Account::childKeys() const
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
 * Removes all the keys in the currently selected service.
 * @see remove(const QString &key)
 */
void Account::clear()
{
    /* clear() must ignore the group: so, temporarily reset it and call
     * remove("") */
    QString saved_prefix = d->prefix;
    d->prefix = QString();
    remove(QString());
    d->prefix = saved_prefix;
}

/*!
 * Checks whether the given key is in the current group.
 * @param key The key name of the settings.
 *
 * This method operates on the currently selected service.
 */
bool Account::contains(const QString &key) const
{
    return childKeys().contains(key);
}

/*!
 * Exits a group.
 *
 * This method operates on the currently selected service.
 */
void Account::endGroup()
{
    d->prefix = d->prefix.section(slash, 0, -3,
                                  QString::SectionIncludeTrailingSep);
    if (!d->prefix.isEmpty() && d->prefix[0] == slash) d->prefix.remove(0, 1);
}

/*!
 * Returns the name of the current group.
 *
 * This method operates on the currently selected service.
 */
QString Account::group() const
{
    if (d->prefix.endsWith(slash))
        return d->prefix.left(d->prefix.size() - 1);
    return d->prefix;
}

/*!
 * Checks whether the account is writable. This always returns true.
 */
bool Account::isWritable() const
{
    return true;
}

/*!
 * Removes the given key. If the key is the empty string, all keys in the
 * current group are removed.
 * @param key The key name of the settings.
 *
 * This method operates on the currently selected service.
 */
void Account::remove(const QString &key)
{
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
        ag_account_set_variant(d->m_account, tmpkey.constData(), NULL);
    }
}

/*!
 * Changes the value of an account setting.
 * @param key The key name of the setting.
 * @param value The new value.
 *
 * This method operates on the currently selected service.
 */
void Account::setValue(const QString &key, const QVariant &value)
{
    GVariant *variant = qVariantToGVariant(value);
    if (variant == nullptr) {
        return;
    }

    QString full_key = d->prefix + key;
    QByteArray tmpkey = full_key.toLatin1();
    ag_account_set_variant(d->m_account, tmpkey.constData(), variant);
}

void Account::Private::account_store_cb(AgAccount *account,
                                        GAsyncResult *res,
                                        Account *self)
{
    GError *error = NULL;
    ag_account_store_finish(account, res, &error);
    if (error) {
        if (error->domain == G_IO_ERROR &&
            error->code == G_IO_ERROR_CANCELLED) {
        } else {
            Q_EMIT self->error(Error(error));
        }
        g_error_free(error);
    } else {
        Q_EMIT self->synced();
    }
}

/*!
 * Retrieves the value of an account setting, as a QVariant.
 * @param key The key whose value must be retrieved.
 * @param defaultValue Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 * @see valueAsString
 * @see valueAsInt
 * @see valueAsBool
 *
 * @return The value associated to \a key.
 *
 * This method operates on the currently selected service.
 */
QVariant Account::value(const QString &key, const QVariant &defaultValue,
                        SettingSource *source) const
{
    QString full_key = d->prefix + key;
    QByteArray ba = full_key.toLatin1();
    AgSettingSource settingSource;
    GVariant *variant =
        ag_account_get_variant(d->m_account, ba.constData(), &settingSource);
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
 * Retrieves the value of an account setting, as a QVariant.
 * @param key The key whose value must be retrieved.
 * @param value A QVariant initialized to the expected type of the value.
 * @see valueAsString
 * @see valueAsInt
 * @see valueAsBool
 *
 * @return Whether the value comes from the account, the service template
 * or was unset.
 *
 * This method operates on the currently selected service.
 * @deprecated Use value(const QString &key, const QVariant &defaultValue,
 * SettingSource *source) const instead.
 */
SettingSource Account::value(const QString &key, QVariant &value) const
{
    SettingSource source;
    QVariant variant = this->value(key, QVariant(), &source);
    if (variant.isValid()) {
        if (value.typeId() != variant.typeId()) {
            if (!variant.convert(value.metaType())) source = NONE;
        }
        value = variant;
    }

    return source;
}

/*!
 * Gets an account setting as a string.
 * @param key The key whose value must be retrieved.
 * @param default_value Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * This method operates on the currently selected service.
 */
QString Account::valueAsString(const QString &key,
                               QString default_value,
                               SettingSource *source) const
{
    QVariant var = default_value;
    SettingSource src = value(key, var);
    if (source)
        *source = src;
    return var.toString();
}

/*!
 * Gets an account setting as an integer.
 * @param key The key whose value must be retrieved.
 * @param default_value Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * This method operates on the currently selected service.
 */
int Account::valueAsInt(const QString &key,
                        int default_value,
                        SettingSource *source) const
{
    QVariant var = default_value;
    SettingSource src = value(key, var);
    if (source)
        *source = src;
    return var.toInt();
}

/*!
 * Gets an account setting as an unsigned long integer.
 * @param key The key of which value must be retrieved.
 * @param default_value Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * This method operates on the currently selected service.
 */
quint64 Account::valueAsUInt64(const QString &key,
                        quint64 default_value,
                        SettingSource *source) const
{
    QVariant var = default_value;
    SettingSource src = value(key, var);
    if (source)
        *source = src;
    return var.toULongLong();
}

/*!
 * Gets an account setting as a boolean.
 * @param key The key whose value must be retrieved.
 * @param default_value Value returned if the key is unset.
 * @param source Indicates whether the value comes from the account, the
 * service template or was unset.
 *
 * This method operates on the currently selected service.
 */
bool Account::valueAsBool(const QString &key,
                          bool default_value,
                          SettingSource *source) const
{
    QVariant var = default_value;
    SettingSource src = value(key, var);
    if (source)
        *source = src;
    return var.toBool();
}

void Watch::Private::account_notify_cb(AgAccount *account, const gchar *key,
                                       Watch *watch)
{
    Q_EMIT watch->notify(key);

    Q_UNUSED(account);
}

/*!
 * Installs a key or group watch.
 *
 * @param key The key to watch; if %NULL, watches the currently selected
 * group.
 *
 * @return A watch object.
 *
 * This method operates on the currently selected service.
 */
Watch *Account::watchKey(const QString &key)
{
    AgAccountWatch ag_watch;
    Watch *watch = new Watch(this);

    if (!key.isEmpty())
    {
        QString full_key = d->prefix + key;
        ag_watch = ag_account_watch_key
            (d->m_account, full_key.toLatin1().constData(),
             (AgAccountNotifyCb)&Watch::Private::account_notify_cb, watch);
    }
    else
    {
        ag_watch = ag_account_watch_dir
            (d->m_account, d->prefix.toLatin1().constData(),
             (AgAccountNotifyCb)&Watch::Private::account_notify_cb, watch);
    }

    if (!ag_watch)
    {
        delete watch;
        return NULL;
    }

    watch->setWatch(ag_watch);
    return watch;
}

/*!
 * Stores all account settings into the database.
 * The signal synced() will be emitted in case of success, or
 * error() in case of failure. No assumption must be made about when these
 * signals will be emitted: if the database is locked, the signals might
 * be emitted asynchronously, whereas if the operation can happen
 * synchronously then the signals can be emitted before this method
 * returns.
 * If for some reason one would want to process the signals asynchronously
 * from the event loop, one can use the Qt::QueuedConnection connection
 * type as last parameter of the QObject::connect call.
 */
void Account::sync()
{
    ag_account_store_async(d->m_account,
                           d->m_cancellable,
                           (GAsyncReadyCallback)&Private::account_store_cb,
                           this);
}

/*!
 * Blocking version of the sync() method: execution of the current thread
 * will block until the operation has completed.
 * Usage of this method is discouraged, especially for UI applications.
 *
 * @return True on success, false otherwise.
 */
bool Account::syncAndBlock()
{
    GError *error = NULL;
    bool ret;

    ret = ag_account_store_blocking(d->m_account, &error);
    if (error)
    {
        qWarning() << "Store operation failed: " << error->message;
        g_error_free(error);
    }

    return ret;
}

/*!
 * Marks the account for removal.
 * The account will be deleted only when the sync() method is called.
 */
void Account::remove()
{
    ag_account_delete(d->m_account);
}

/*!
 * Creates signature of key with given aegis token. The calling application
 * must possess (request) the given aegis token. The account needs to be
 * stored prior to executing this method.
 * @param key The key or the prefix of set of the keys to be signed.
 * @param token The aegis token to be used for signing the key.
 *
 * This method operates on the currently selected service.
 */
void Account::sign(const QString &key, const char *token)
{
    ag_account_sign (d->m_account, key.toUtf8().constData(), token);
}

/*!
 * Verifies if the key is signed and the signature matches the value
 * and provides the aegis token which was used for signing the key.
 *
 * @param key The name of the key or prefix of the keys to be verified.
 * @param token Aegis token to be retrieved.
 *
 * @return True if the key is signed and the signature matches the value.
 *
 * This method operates on the currently selected service.
 */
bool Account::verify(const QString &key, const char **token)
{
    return ag_account_verify(d->m_account, key.toUtf8().constData(), token);
}

/*!
 * Verifies if the key is signed with any of the aegis tokens and the
 * signature is valid.
 *
 * @param key The name of the key or prefix of the keys to be verified.
 * @param tokens Array of aegis tokens.
 *
 * @return True if the key is signed with any of the aegis tokens and
 * the signature is valid.
 *
 * This method operates on the currently selected service.
 */
bool Account::verifyWithTokens(const QString &key, QList<const char*> tokens)
{
    int tokensCount = tokens.count();

    const char *tmp[tokensCount + 1];

    for (int i = 0; i < tokensCount; ++i)
    {
        tmp[i] = tokens.at(i);
    }
    tmp[tokensCount] = NULL;

    return ag_account_verify_with_tokens(d->m_account, key.toUtf8().constData(), tmp);
}

uint Account::credentialsId()
{
    QString key = ACCOUNTS_KEY_CREDENTIALS_ID;
    QVariant val(QMetaType(QMetaType::Int));

    if (value(key, val) != NONE)
        return val.toUInt();

    uint id = 0;
    Service service = selectedService();
    if (service.isValid()) {
        selectService();
        if (value(key, val) != NONE)
            id = val.toUInt();
        selectService(service);
    }
    return id;
}

AgAccount *Account::account()
{
    return d->m_account;
}
