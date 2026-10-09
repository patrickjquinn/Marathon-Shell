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

#ifndef ACCOUNTINTERFACE_H
#define ACCOUNTINTERFACE_H

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtCore/QStringList>
#include <QtCore/QString>

#include <QtGlobal>
#if QT_VERSION_5
#include <QtQml>
#include <QQmlParserStatus>
#define QDeclarativeParserStatus QQmlParserStatus
#else
#include <qdeclarative.h>
#include <QDeclarativeParserStatus>
#endif

//libaccounts-qt
#include <Accounts/Account>
#include <Accounts/Error>

class AccountInterfacePrivate;
class AccountManagerInterface;

/*
 * NOTE: if you construct one of these in C++ directly,
 * you MUST call classBegin() and componentCompleted()
 * directly after construction.
 */

class AccountInterface : public QObject, public QDeclarativeParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QDeclarativeParserStatus)

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int identifier READ identifier WRITE setIdentifier NOTIFY identifierChanged)
    Q_PROPERTY(QVariantMap identityIdentifiers READ identityIdentifiers NOTIFY identityIdentifiersChanged)
    Q_PROPERTY(QString providerName READ providerName WRITE setProviderName NOTIFY providerNameChanged)

    Q_PROPERTY(QString displayName READ displayName WRITE setDisplayName NOTIFY displayNameChanged)

    Q_PROPERTY(QStringList supportedServiceNames READ supportedServiceNames NOTIFY supportedServiceNamesChanged)
    Q_PROPERTY(QStringList enabledServiceNames READ enabledServiceNames NOTIFY enabledServiceNamesChanged)

    Q_PROPERTY(QVariantMap configurationValues READ configurationValues WRITE setConfigurationValues NOTIFY configurationValuesChanged)

    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(ErrorType error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    Q_ENUMS(Status)
    Q_ENUMS(ErrorType)

public:
    enum Status {
        Initialized = 0,
        Initializing,
        Synced,
        SyncInProgress,
        Modified,
        Error,
        Invalid
    };

    enum ErrorType {
        NoError                 = Accounts::Error::NoError,
        UnknownError            = Accounts::Error::Unknown,
        DatabaseError           = Accounts::Error::Database,
        DeletedError            = Accounts::Error::Deleted,
        DatabaseLockedError     = Accounts::Error::DatabaseLocked,
        AccountNotFoundError    = Accounts::Error::AccountNotFound,
        ConflictingProviderError,
        InitializationFailedError
    };

public:
    AccountInterface(QObject *parent = 0);
    ~AccountInterface();

    // QDeclarativeParserStatus
    void classBegin();
    void componentComplete();

    // database sync
    Q_INVOKABLE void sync();
    Q_INVOKABLE void remove();

    // invokable api.
    Q_INVOKABLE void setConfigurationValue(const QString &key, const QVariant &value, const QString &serviceName = QString());
    Q_INVOKABLE void removeConfigurationValue(const QString &key, const QString &serviceName = QString());
    Q_INVOKABLE QVariantMap serviceConfigurationValues(const QString &serviceName) const;
    Q_INVOKABLE void setConfigurationValues(const QVariantMap &values, const QString &serviceName);
    Q_INVOKABLE QString encodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const;
    Q_INVOKABLE QString decodeConfigurationValue(const QString &value, const QString &scheme = QString(), const QString &key = QString()) const;

    Q_INVOKABLE bool supportsServiceType(const QString &serviceType);
    Q_INVOKABLE void enableWithService(const QString &serviceName);
    Q_INVOKABLE void disableWithService(const QString &serviceName);

    Q_INVOKABLE int identityIdentifier(const QString &serviceName = QString()) const;
    Q_INVOKABLE void setIdentityIdentifier(int id, const QString &serviceName = QString());

    // property accessors.
    bool enabled() const;
    void setEnabled(bool e);
    int identifier() const;
    void setIdentifier(int id);
    QVariantMap identityIdentifiers() const;
    QString displayName() const;
    void setDisplayName(const QString &dn);
    QString providerName() const;
    void setProviderName(const QString &pname);
    QStringList supportedServiceNames() const;
    QStringList enabledServiceNames() const;
    QVariantMap configurationValues() const;
    void setConfigurationValues(const QVariantMap &values);

    Status status() const;
    ErrorType error() const;
    QString errorMessage() const;

Q_SIGNALS:
    void enabledChanged();
    void identifierChanged();
    void identityIdentifiersChanged();
    void displayNameChanged();
    void providerNameChanged();
    void supportedServiceNamesChanged();
    void enabledServiceNamesChanged();
    void configurationValuesChanged();
    void statusChanged();
    void errorChanged();
    void errorMessageChanged();

private:
    AccountInterface(Accounts::Account *account, QObject *parent = 0);
    Accounts::Account *account();
    friend class AccountManagerInterface;

private:
    AccountInterfacePrivate *d;
    friend class AccountInterfacePrivate;
};

#endif
