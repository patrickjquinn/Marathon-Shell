// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* Copyright (C) 2021 Jolla Ltd.
 *
 * Contact: Juho Hämäläinen <juho.hamalainen@jolla.com>
 *
 * This work is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1 as published by the Free Software Foundation.
 *
 * This work is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this work; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 */


#ifndef DECLARATIVENGFEVENTPROPERTY_H
#define DECLARATIVENGFEVENTPROPERTY_H

#include <QObject>
#include <QVariant>

class DeclarativeNgfEventProperty : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QVariant value READ value WRITE setValue NOTIFY valueChanged)
public:
    DeclarativeNgfEventProperty(QObject *parent = nullptr);

    QString name() const;
    void setName(const QString &);

    QVariant value() const;
    void setValue(const QVariant &);

signals:
    void nameChanged();
    void valueChanged();

private:
    QString m_name;
    QVariant m_value;
};

#endif
