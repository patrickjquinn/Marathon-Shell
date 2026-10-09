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

#ifndef ACCOUNTMANAGERINTERFACE_H
#define ACCOUNTMANAGERINTERFACE_H

#include <QtCore/QObject>

#include <QtGlobal>
#if QT_VERSION_5
#include <QtQml>
#include <QQmlParserStatus>
#define QDeclarativeParserStatus QQmlParserStatus
#else
#include <qdeclarative.h>
#include <QDeclarativeParserStatus>
#endif

#include <QtCore/QStringList>
#include <QtCore/QString>

class AccountManagerInterfacePrivate;
class ServiceTypeInterface;
class ProviderInterface;
class ServiceInterface;
class AccountInterface;
// Modified by Shipwright for Qt 6 (this copy builds for Qt 6 only): moc
// needs the complete pointer types.
Q_MOC_INCLUDE("servicetypeinterface.h")
Q_MOC_INCLUDE("providerinterface.h")
Q_MOC_INCLUDE("serviceinterface.h")
Q_MOC_INCLUDE("accountinterface.h")
class ServiceAccountInterface;

/*
 * AccountManagerInterface
 *
 * Lightweight adapter for QML, providing access to various API from
 * libaccounts-qt Manager.  Intended for use by the settings app
 * only - not for 3rd party application developers.
 */
class AccountManagerInterface : public QObject, public QDeclarativeParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QDeclarativeParserStatus)

    // if database transactions take longer than timeout, an error signal will be emitted... TODO.
    Q_PROPERTY(int timeout READ timeout WRITE setTimeout NOTIFY timeoutChanged)

    // the manager will only provide providers, services and accounts which are valid for the specified service type (or all, if empty)
    Q_PROPERTY(QString serviceTypeFilter READ serviceTypeFilter WRITE setServiceTypeFilter NOTIFY serviceTypeFilterChanged)

    // we provide a list of available service types.  These can be used to filter, via the serviceTypeFilter property.
    Q_PROPERTY(QStringList serviceTypeNames READ serviceTypeNames NOTIFY serviceTypeNamesChanged)

    // the real API is via these properties and the invokable accessors.
    Q_PROPERTY(QStringList providerNames READ providerNames NOTIFY providerNamesChanged)
    Q_PROPERTY(QStringList serviceNames READ serviceNames NOTIFY serviceNamesChanged)
    Q_PROPERTY(QStringList accountIdentifiers READ accountIdentifiers NOTIFY accountIdentifiersChanged) // QtQuick1 doesn't support QList<int> etc.

public:
    AccountManagerInterface(QObject *parent = 0);
    ~AccountManagerInterface();

    // invokable api.
    Q_INVOKABLE AccountInterface *createAccount(const QString &providerName);
    Q_INVOKABLE void removeAccount(AccountInterface *account);

    Q_INVOKABLE ServiceTypeInterface *serviceType(const QString &serviceTypeName) const;

    Q_INVOKABLE ServiceInterface *service(const QString &serviceName) const;
    Q_INVOKABLE ProviderInterface *provider(const QString &providerName) const;
    Q_INVOKABLE AccountInterface *account(const QString &accountIdentifier) const;
    Q_INVOKABLE AccountInterface *account(int accountIdentifier) const;
    Q_INVOKABLE ServiceAccountInterface *serviceAccount(const QString &accountIdentifier, const QString &serviceName) const;
    Q_INVOKABLE ServiceAccountInterface *serviceAccount(int accountIdentifier, const QString &serviceName) const;
    Q_INVOKABLE ServiceAccountInterface *serviceAccountFromProvider(const QString &providerName, const QString &serviceName = QString()) const;

    // property accessors and mutators.
    int timeout() const;
    void setTimeout(int t);
    QString serviceTypeFilter() const;
    void setServiceTypeFilter(const QString &stname);
    QStringList serviceTypeNames() const;
    QStringList providerNames() const;
    QStringList serviceNames() const;
    QStringList accountIdentifiers() const;

    // QDeclarativeParserStatus - for perf, delay construction of internal ptrs until properties are initialized.
    void classBegin();
    void componentComplete();

Q_SIGNALS:
    void timeoutChanged();
    void serviceTypeFilterChanged();
    void serviceTypeNamesChanged();
    void providerNamesChanged();
    void serviceNamesChanged();
    void accountIdentifiersChanged();

private:
    AccountManagerInterfacePrivate *d;
    friend class AccountManagerInterfacePrivate;
};

#endif
