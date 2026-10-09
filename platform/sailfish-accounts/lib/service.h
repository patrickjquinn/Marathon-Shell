/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__SERVICE_H
#define SAILFISH_ACCOUNTS__SERVICE_H

#include <QtCore/QObject>
#include <QStringList>
#include <QString>

// libaccounts-qt
#include <Accounts/Service>

class Q_DECL_EXPORT Service : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString displayName READ displayName CONSTANT)
    Q_PROPERTY(QString serviceType READ serviceType CONSTANT)
    Q_PROPERTY(QString providerName READ providerName CONSTANT)
    Q_PROPERTY(QString iconName READ iconName CONSTANT)
    Q_PROPERTY(QStringList tags READ tags CONSTANT)

public:
    Service(const Accounts::Service &service = Accounts::Service(), QObject *parent = 0);
    ~Service();

    // property accessors.
    QString name() const;
    QString displayName() const;
    QString serviceType() const;
    QString providerName() const;
    QString iconName() const;
    QStringList tags() const;

private:
    Accounts::Service m_service;
};

#endif
