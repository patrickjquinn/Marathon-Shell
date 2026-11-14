// SPDX-FileCopyrightText: 2011-2012 Timur Kristóf
// SPDX-License-Identifier: LGPL-2.1-only


// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2011-2012, Timur Kristóf <venemo@fedoraproject.org>

#ifndef QOBJECTLISTMODEL_H
#define QOBJECTLISTMODEL_H

#include <QAbstractListModel>

#include "lipstickglobal.h"

class LIPSTICK_EXPORT QObjectListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int itemCount READ itemCount NOTIFY itemCountChanged)

    QList<QObject*> *_list;
    QList<QObject*> _inserted;
    QList<QObject*> _removed;

public:
    explicit QObjectListModel(QObject *parent = 0, QList<QObject*> *list = new QList<QObject*>());

    QHash<int, QByteArray> roleNames() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const;
    int itemCount() const;
    int columnCount(const QModelIndex &parent = QModelIndex()) const;
    QVariant data(const QModelIndex &index, int role) const;
    bool setData(const QModelIndex &index, const QVariant &value, int role);
    Q_INVOKABLE void reset();
    Q_INVOKABLE void move(int oldRow, int newRow);
    Q_INVOKABLE void update(int row);

    void insertItem(int index, QObject *item);
    void addItem(QObject *item);
    void addItems(const QList<QObject *> &items);
    void removeItem(QObject *item);
    void removeItems(const QList<QObject *> &items);
    void removeItem(int index);
    Q_INVOKABLE QObject* get(int index);
    Q_INVOKABLE int indexOf(QObject *obj) const;

    template<typename T>
    QList<T*> *getList();
    QList<QObject*> *getList();

    template<typename T>
    void setList(QList<T*> *list);
    void setList(QList<QObject*> *list);

    template<typename T>
    void synchronizeList(const QList<T*> &list);
    void synchronizeList(const QList<QObject*> &list);

    // For synchronizeLists()
    int insertRange(int index, int count, const QList<QObject *> &source, int sourceIndex);
    int removeRange(int index, int count);

private slots:
    void removeDestroyedItem();

signals:
    void itemAdded(QObject *item);
    void itemRemoved(QObject *item);
    void itemCountChanged();
};

template<typename T>
QList<T*> *QObjectListModel::getList()
{
    return reinterpret_cast<QList<T *> *>(_list);
}

template<typename T>
void QObjectListModel::setList(QList<T*> *list)
{
    setList(reinterpret_cast<QList<QObject *> *>(list));
}

template<typename T>
void QObjectListModel::synchronizeList(const QList<T*> &list)
{
    synchronizeList(reinterpret_cast<const QList<QObject *> &>(list));
}

#endif // QOBJECTLISTMODEL_H
