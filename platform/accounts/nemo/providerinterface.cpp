// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd. <chris.adams@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "providerinterface.h"

//libaccounts-qt
#include <Accounts/Manager>

class ProviderInterfacePrivate
{
public:
    Accounts::Provider provider;
    QStringList serviceNames;
};

/*!
    \qmltype Provider
    \instantiates ProviderInterface
    \inqmlmodule org.nemomobile.accounts 1
    \brief Reports information about a given provider

    Every account is specified for a particular provider.
    Every provider can have one or more services associated
    with it.  Each account may be enabled with zero or more
    services from the provider.

    This type is purely informational, and reports information
    about the provider of the account.  The information is
    specified in the \c{.provider} file installed by the
    account provider plugin.
*/

ProviderInterface::ProviderInterface(const Accounts::Provider &provider, QObject *parent)
    : QObject(parent), d(new ProviderInterfacePrivate)
{
    d->provider = provider;

    // first time fetch of service names.
    Accounts::Manager m;
    Accounts::ServiceList services = m.serviceList();
    foreach (const Accounts::Service &srv, services) {
        if (srv.provider() == d->provider.name()) {
            d->serviceNames.append(srv.name());
        }
    }
}

ProviderInterface::~ProviderInterface()
{
    delete d;
}

/*!
    \qmlproperty string Provider::name
    The name of the provider.
*/

QString ProviderInterface::name() const
{
    return d->provider.name();
}

/*!
    \qmlproperty string Provider::displayName
    The display name of the provider.  This display name
    can be displayed in lists or dialogues in the UI.
*/

QString ProviderInterface::displayName() const
{
    return d->provider.displayName();
}

/*!
    \qmlproperty string Provider::iconName
    The name of the icon associated with the provider.
*/

QString ProviderInterface::iconName() const
{
    return d->provider.iconName();
}

/*!
    \qmlproperty QStringList Provider::serviceNames
    The names of services provided by this provider.
*/

QStringList ProviderInterface::serviceNames() const
{
    return d->serviceNames;
}

