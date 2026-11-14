// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*!
 *
 * Copyright (C) 2021 Jolla Ltd.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef MPRISMETADATA_P_H
#define MPRISMETADATA_P_H

#include "mprismetadata.h"
#include <QObject>
#include <QVariantMap>
#include <QMap>
#include <QTimer>
#include <QPointer>
#include <QSet>

namespace Amber {
class MprisMetaDataPrivate : public QObject
{
    Q_OBJECT

public:
    MprisMetaDataPrivate(MprisMetaData *metaData);
    ~MprisMetaDataPrivate();

    QVariantMap typedMetaData() const;
    void setMetaData(const QString &key, const QVariant &value);
    void setMetaData(const QVariantMap &metaData);

public Q_SLOTS:
    void fillFromPropertyChange();
    void fillFrom();

public:
    MprisMetaData *q_ptr;
    QVariantMap m_metaData;
    QTimer m_changedDelay;
    QTimer m_fillFromDelay;
    QVariant m_fillFrom;
    QPointer<QObject> m_fillFromObject;
    QMap<int, QList<const char *>> m_signalPropertyMap;
    QSet<const char *> m_changedProperties;
};
}

#endif
