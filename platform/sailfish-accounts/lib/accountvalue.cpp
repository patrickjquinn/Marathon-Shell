// SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include <QDebug>

#include "accountvalue.h"

AccountValuePrivate::AccountValuePrivate(AccountValue *parent)
    : QObject(parent)
    , m_account(nullptr)
    , m_service()
    , m_key()
    , m_targetProperty()
    , m_watch(nullptr)
    , m_changed(false)
    , m_conflict(false)
    , m_initialised(false)
    , m_enabled(true)
    , m_delayInitialisation(false)
    , q(parent)
{
}

AccountValuePrivate::~AccountValuePrivate()
{
    if (m_watch) {
        disconnect(m_watch, nullptr, this, nullptr);
        delete m_watch;
        m_watch = nullptr;
    }
    if (m_account) {
        disconnect(m_account, &Account::statusChanged, this, nullptr);
    }
}

AccountValue::AccountValue(QObject *parent)
    : QObject(parent)
    , d(new AccountValuePrivate(this))
{
}

AccountValue::~AccountValue()
{
}

Account *AccountValue::account() const
{
    return d->m_account;
}

QString AccountValue::service() const
{
    return d->m_service;
}

QString AccountValue::key() const
{
    return d->m_key;
}

void AccountValuePrivate::onAccountDestroyed()
{
    if (m_account) {
        disconnect(m_account, nullptr, this, nullptr);
        m_account = nullptr;
    }
    if (m_watch) {
        disconnect(m_watch, nullptr, this, nullptr);
        // Don't delete the watch, it'll be deleted with its parent account
        m_watch = nullptr;
    }
    m_initialised = false;
}

void AccountValue::setAccount(Account *account)
{
    if (d->m_account != account) {
        d->m_initialised = false;
        if (d->m_account) {
            disconnect(d->m_account, &Account::statusChanged, d, &AccountValuePrivate::onAccountStatusChanged);
        }
        d->m_account = account;
        if (d->m_account) {
            connect(d->m_account, &QObject::destroyed, d, &AccountValuePrivate::onAccountDestroyed);
            connect(d->m_account, &Account::statusChanged, d, &AccountValuePrivate::onAccountStatusChanged);
        }
        d->initialise();
        emit accountChanged();
    }
}

void AccountValue::setService(QString &service)
{
    if (d->m_service != service) {
        d->m_initialised = false;
        d->m_service = service;
        d->initialise();
        emit serviceChanged();
    }
}

void AccountValue::setKey(QString &key)
{
    if (d->m_key != key) {
        d->m_initialised = false;
        d->m_key = key;
        d->initialise();
        emit keyChanged();
    }
}

void AccountValue::setTarget(const QQmlProperty &prop)
{
    d->m_targetProperty = prop;
    d->m_targetProperty.connectNotifySignal(d, SLOT(onTargetValueChanged()));
    clearLocalChanged();
}

void AccountValuePrivate::onAccountStatusChanged()
{
    initialise();
}

Accounts::Service AccountValuePrivate::getService(const QString serviceName) const
{
    if (!serviceName.isEmpty() && m_account && m_account->account()) {
        Accounts::ServiceList const services = m_account->account()->services();
        for (Accounts::Service service : services) {
            if (service.name() == serviceName) {
                return service;
            }
        }
    }
    return Accounts::Service();
}

void AccountValuePrivate::initialise()
{
    if (m_initialised) {
        // No need to initialise twice
        return;
    }

    if (m_delayInitialisation) {
        // Avoid initialising while QML components are being created
        return;
    }

    if (m_watch) {
        // Connected signal will be disconnected automatically
        delete m_watch;
        m_watch = nullptr;
    }
    if (setupComplete()) {
        Accounts::Account * const account = m_account->account();
        Accounts::Service const service = getService(m_service);
        account->selectService(service);

        m_watch = account->watchKey(m_key);
        connect(m_watch, &Accounts::Watch::notify, this, &AccountValuePrivate::onRemoteValueChanged);
        m_initialised = true;
    }
    q->clearLocalChanged();
}

void AccountValuePrivate::updateTargetFromRemote()
{
    if (m_enabled && setupComplete() && m_targetProperty.isProperty()) {
        Accounts::Account * const account = m_account->account();
        Accounts::Service const service = getService(m_service);
        account->selectService(service);
        QVariant value = account->value(m_key);
        m_account->setConfigurationValue(m_service, m_key, value);
        m_targetProperty.write(value);
    }
}

void AccountValuePrivate::onRemoteValueChanged(const char *)
{
    if (!m_changed) {
        updateTargetFromRemote();
        emit q->remoteValueChanged();
    } else {
        QVariant const remote = q->remoteValue();
        if (remote != m_targetProperty.read()) {
            m_conflict = true;
            emit q->conflictChanged();
        }
    }
}

void AccountValuePrivate::onTargetValueChanged()
{
    if (m_enabled && setupComplete()) {
        QVariant const accountValue = m_account->configurationValue(m_service, m_key);
        QVariant const targetValue = m_targetProperty.read();

        if (accountValue != targetValue) {
            m_account->setConfigurationValue(m_service, m_key, targetValue);
            m_changed = true;
        }
    }
}

void AccountValue::clearLocalChanged()
{
    d->m_changed = false;
    d->updateTargetFromRemote();
    if (d->m_conflict) {
        d->m_conflict = false;
        emit conflictChanged();
    }
}

bool AccountValue::conflict() const
{
    return d->m_conflict;
}

QVariant AccountValue::remoteValue() const
{
    QVariant value;

    if (d->setupComplete()) {
        Accounts::Account * const account = d->m_account->account();
        Accounts::Service const service = d->getService(d->m_service);
        account->selectService(service);
        value = account->value(d->m_key);
    }
    return value;
}

bool AccountValuePrivate::setupComplete() const
{
    return !m_key.isEmpty() && !m_service.isNull()
            && m_account && m_account->account()
            && (m_account->status() == Account::Initialized
                || m_account->status() == Account::Synced
                || m_account->status() == Account::Modified);
}

bool AccountValue::enabled() const
{
    return d->m_enabled;
}

void AccountValue::setEnabled(bool enabled)
{
    if (d->m_enabled != enabled) {
        d->m_enabled = enabled;
        emit enabledChanged();
    }
}

void AccountValuePrivate::classBegin()
{
    m_delayInitialisation = true;
}

void AccountValuePrivate::componentComplete()
{
    m_delayInitialisation = false;
    initialise();
}
