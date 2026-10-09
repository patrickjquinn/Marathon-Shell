/*
 * SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTVALUE_H
#define SAILFISH_ACCOUNTS__ACCOUNTVALUE_H

#include <QQmlPropertyValueSource>
#include <QQmlProperty>

#include "account.h"

class AccountValuePrivate;

/*!
    \qmlclass Accountvalue

    Attaches dynamic account configuration update behaviour to a property

    If the configuration value changes in the background the property will be
    updated to reflect the change. If the property changes first then the
    relationship is broken and background changes of the value are no longer
    reflected in the property.

    Attach it to a QML property like this:

    AccountValue on <property> { account: <account>; service: "<service>"; key: "<key>"}
*/
class Q_DECL_EXPORT AccountValue : public QObject, public QQmlPropertyValueSource
{
    Q_OBJECT
    Q_INTERFACES(QQmlPropertyValueSource)

    Q_PROPERTY(Account *account READ account WRITE setAccount NOTIFY accountChanged)
    Q_PROPERTY(QString service READ service WRITE setService NOTIFY serviceChanged)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

    // A conflict occurs if both the remote and local values are changed independently
    Q_PROPERTY(bool conflict READ conflict NOTIFY conflictChanged)
    Q_PROPERTY(QVariant remoteValue READ remoteValue NOTIFY remoteValueChanged)

public:
    AccountValue(QObject *parent = nullptr);
    ~AccountValue() override;

    Account *account() const;
    QString service() const;
    QString key() const;
    bool conflict() const;
    QVariant remoteValue() const;
    bool enabled() const;

    void setAccount(Account *account);
    void setService(QString &service);
    void setKey(QString &key);
    void setEnabled(bool enabled);

    Q_INVOKABLE void clearLocalChanged();

    virtual void setTarget(const QQmlProperty &prop) override;

signals:
    void accountChanged();
    void serviceChanged();
    void keyChanged();
    void conflictChanged();
    void remoteValueChanged();
    void enabledChanged();

private:
    AccountValuePrivate * d;
};

class AccountValuePrivate : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)

public:
    AccountValuePrivate(AccountValue *parent = nullptr);
    ~AccountValuePrivate() override;

    void initialise();
    Accounts::Service getService(const QString serviceName) const;
    void updateTargetFromRemote();
    bool setupComplete() const;

    // QQmlParserStatus callbacks
    void classBegin() override;
    void componentComplete() override;

public slots:
    void onRemoteValueChanged(const char *key);
    void onTargetValueChanged();
    void onAccountStatusChanged();
    void onAccountDestroyed();

public:
    Account *m_account;
    QString m_service;
    QString m_key;
    QQmlProperty m_targetProperty;
    Accounts::Watch *m_watch;
    bool m_changed;
    bool m_conflict;
    bool m_initialised;
    bool m_enabled;
    bool m_delayInitialisation;

    AccountValue *q;
};

#endif // SAILFISH_ACCOUNTS__ACCOUNTVALUE_H
