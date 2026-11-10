/*
 * SPDX-FileCopyrightText: 2013 - 2024 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__SIGNINPARAMETERS_H
#define SAILFISH_ACCOUNTS__SIGNINPARAMETERS_H

#include <QObject>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QVariant>

class Account;

class Q_DECL_EXPORT SignInParameters : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serviceName READ serviceName CONSTANT)
    Q_PROPERTY(QString method READ method CONSTANT)
    Q_PROPERTY(QString mechanism READ mechanism CONSTANT)
    Q_PROPERTY(QVariantMap parameters READ parameters NOTIFY parametersChanged)
    Q_PROPERTY(QString username READ username CONSTANT)
    Q_PROPERTY(QString password READ password CONSTANT)

    Q_ENUMS(UiPolicy)
    Q_ENUMS(CredentialsPolicy)

public:
    // Matching libsignon enum values, but avoiding using them directly so we don't need
    // to expose dependency on the API just because of this thing
    enum UiPolicy {
        DefaultPolicy           = 0, // SignOn::DefaultPolicy,
        RequestPasswordPolicy   = 1, // SignOn::RequestPasswordPolicy,
        NoUserInteractionPolicy = 2, // SignOn::NoUserInteractionPolicy,
        ValidationPolicy        = 3  // SignOn::ValidationPolicy
    };

    enum CredentialsPolicy {
        UseCachedCredentialsPolicy = 0,
        RefreshCredentialsPolicy = 1
    };

public:
    ~SignInParameters();
    SignInParameters(const QString &serviceName = QString(),
                     const QString &method = QString(),
                     const QString &mechanism = QString(),
                     const QVariantMap &parameters = QVariantMap(),
                     const QString &username = QString(),
                     const QString &password = QString(),
                     QObject *parent = 0);

    // property accessors.
    QString serviceName() const;
    QString method() const;
    QString mechanism() const;
    QVariantMap parameters() const;
    QString username() const;
    QString password() const;

    // invokable api.
    Q_INVOKABLE void setParameters(const QVariantMap &parameters);
    Q_INVOKABLE void setParameter(const QString &parameterName, const QVariant &parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, const QString &parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, const QStringList &parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, const QUrl &parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, int parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, bool parameterValue);
    Q_INVOKABLE void setParameter(const QString &parameterName, const QVariantMap &parameterValue);
    Q_INVOKABLE void removeParameter(const QString &parameterName);

Q_SIGNALS:
    void parametersChanged();

private:
    QString m_serviceName;
    QString m_method;
    QString m_mechanism;
    QVariantMap m_parameters;
    QString m_username;
    QString m_password;
};

#endif
