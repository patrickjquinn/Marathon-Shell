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

#ifndef SERVICEACCOUNTINTERFACE_H
#define SERVICEACCOUNTINTERFACE_H

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtCore/QString>

//libaccounts-qt
#include <Accounts/AccountService>

class ServiceAccountInterfacePrivate;
class ProviderInterface;
class ServiceInterface;
class AuthDataInterface;
// Modified by Shipwright for Qt 6 (this copy builds for Qt 6 only): moc
// needs the complete pointer types.
Q_MOC_INCLUDE("providerinterface.h")
Q_MOC_INCLUDE("serviceinterface.h")
Q_MOC_INCLUDE("authdatainterface.h")

/*
 * ServiceAccountInterface
 * Exposes the functionality of a particular account for a particular
 * service, to QML.  It is intended to be used by client applications
 * who need to use an account to access a service or resource.
 */
class ServiceAccountInterface : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)
    Q_PROPERTY(int identifier READ identifier CONSTANT)
    Q_PROPERTY(AuthDataInterface *authData READ authData CONSTANT)
    Q_PROPERTY(ServiceInterface *service READ service CONSTANT)
    Q_PROPERTY(ProviderInterface *provider READ provider CONSTANT)
    Q_PROPERTY(QVariantMap configurationValues READ configurationValues NOTIFY configurationValuesChanged)

public:
    enum OwnershipSemantic { // does it own the Accounts::AccountService instance.
        DoesNotHaveOwnership = 0,
        HasOwnership = 1
    };

    ServiceAccountInterface(Accounts::AccountService *serviceAccount, OwnershipSemantic os = DoesNotHaveOwnership, QObject *parent = 0);
    ~ServiceAccountInterface();

    // invokable api.
    Q_INVOKABLE void setConfigurationValue(const QString &key, const QVariant &value);
    Q_INVOKABLE void removeConfigurationValue(const QString &key);
    Q_INVOKABLE QVariantMap unrelatedValues() const; // from Account class, all keys/values regardless of service
    Q_INVOKABLE QString encodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const;
    Q_INVOKABLE QString decodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const;

    // property accessors.
    bool enabled() const;
    int identifier() const;
    AuthDataInterface *authData() const;
    ServiceInterface *service() const;
    ProviderInterface *provider() const;
    QVariantMap configurationValues() const;

Q_SIGNALS:
    void enabledChanged();
    void configurationValuesChanged();

private:
    ServiceAccountInterfacePrivate *d;
    friend class ServiceAccountInterfacePrivate;
};

#endif
