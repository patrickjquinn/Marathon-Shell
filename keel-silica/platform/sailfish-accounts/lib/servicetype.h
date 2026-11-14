/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__SERVICETYPE_H
#define SAILFISH_ACCOUNTS__SERVICETYPE_H

#include <QtCore/QObject>
#include <QStringList>
#include <QString>

// libaccounts-qt
#include <Accounts/ServiceType>

class Q_DECL_EXPORT ServiceType : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString displayName READ displayName CONSTANT)
    Q_PROPERTY(QString iconName READ iconName CONSTANT)
    Q_PROPERTY(QStringList tags READ tags CONSTANT)

public:
    ServiceType(const Accounts::ServiceType &serviceType = Accounts::ServiceType(), QObject *parent = 0);
    ~ServiceType();

    QString name() const;
    QString displayName() const;
    QString iconName() const;
    QStringList tags() const;

private:
    Accounts::ServiceType m_serviceType;
};

#endif
