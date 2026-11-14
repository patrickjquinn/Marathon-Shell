// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2017 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "provider.h"
#include "globalaccountmanager_p.h"
#include "globaltranslatorcache_p.h"
#include <QTranslator>

// libaccounts-qt
#include <Accounts/Manager>

/*!
    \qmltype Provider
    \instantiates Provider
    \inqmlmodule Sailfish.Accounts 1
    \brief Reports information about a given provider

    Every account is specified for a particular provider.
    Every provider can have one or more services associated
    with it.  Each account may be enabled with zero or more
    services from the provider.

    This type is purely informational, and reports information
    about the provider of the account.  The information is
    specified in the \c{.provider} file installed by the
    \l {https://docs.sailfishos.org/Reference/Core_Areas_and_APIs/Apps_and_MW/Accounts_and_SSO/Providers_and_Services} {account provider plugin}.
*/

Provider::Provider(const Accounts::Provider &provider, QObject *parent)
    : QObject(parent), m_provider(provider)
{
    // first time fetch of service names.
    Accounts::Manager *m = globalAccountManager();
    Accounts::ServiceList services = m->serviceList();
    foreach (const Accounts::Service &srv, services) {
        if (srv.provider() == m_provider.name()) {
            m_serviceNames.append(srv.name());
        }
    }
}

Provider::~Provider()
{
}

/*!
    \qmlproperty string Provider::name
    The name of the provider.
*/

QString Provider::name() const
{
    return m_provider.name();
}

/*!
    \qmlproperty string Provider::displayName
    The display name of the provider.  This display name
    can be displayed in lists or dialogues in the UI.
*/

QString Provider::displayName() const
{
    return SailfishAccounts::translatedDisplayName(m_provider);
}

/*!
    \qmlproperty string Provider::iconName
    The name of the icon associated with the provider.
*/

QString Provider::iconName() const
{
    return m_provider.iconName();
}

/*!
    \qmlproperty list Provider::serviceNames
    The names of services provided by this provider.
*/

QStringList Provider::serviceNames() const
{
    return m_serviceNames;
}

/*!
    \qmlproperty bool Provider::singleAccount
    Whether the provider supports creating one account at most.
*/

bool Provider::isSingleAccount() const
{
    return m_provider.isSingleAccount();
}
