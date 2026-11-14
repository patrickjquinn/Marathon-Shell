// SPDX-FileCopyrightText: 2012 Timur Kristóf
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
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#include "qobjectlistmodel.h"
#include "synchronizelists.h"
#include <QQmlEngine>
#include <QDebug>

QObjectListModel::QObjectListModel(QObject *parent, QList<QObject*> *list)
    : QAbstractListModel(parent),
      _list(list)
{
}

QHash<int, QByteArray> QObjectListModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[Qt::UserRole + 1] = "object";
    return roles;
}

int QObjectListModel::indexOf(QObject *obj) const
{
    return _list->indexOf(obj);
}

int QObjectListModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return _list->count();
}

int QObjectListModel::itemCount() const
{
    return _list->count();
}

int QObjectListModel::columnCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return 1;
}

QVariant QObjectListModel::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= _list->count())
        return QVariant();

    if (role == Qt::UserRole + 1) {
        QObject *obj = _list->at(index.row());
        return QVariant::fromValue(obj);
    }

    return QVariant(0);
}

bool QObjectListModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (index.row() < 0 || index.row() >= _list->count())
        return false;

    if (role == Qt::UserRole + 1) {
        _list->replace(index.row(), reinterpret_cast<QObject*>(value.toInt()));
        return true;
    }

    return false;
}

void QObjectListModel::insertItem(int index, QObject *item)
{
    beginInsertRows(QModelIndex(), index, index);
    _list->insert(index, item);
    connect(item, &QObject::destroyed,
            this, &QObjectListModel::removeDestroyedItem);
    endInsertRows();

    emit itemAdded(item);
    emit itemCountChanged();
}

void QObjectListModel::addItem(QObject *item)
{
    insertItem(_list->count(), item);
}

void QObjectListModel::addItems(const QList<QObject *> &items)
{
    if (!items.isEmpty()) {
        int index(_list->count());
        beginInsertRows(QModelIndex(), index, (index + items.count() - 1));
        foreach (QObject *item, items) {
            _list->append(item);
            connect(item, &QObject::destroyed,
                    this, &QObjectListModel::removeDestroyedItem);
        }
        endInsertRows();

        foreach (QObject *item, items) {
            emit itemAdded(item);
        }
        emit itemCountChanged();
    }
}

void QObjectListModel::removeDestroyedItem()
{
    QObject *obj = QObject::sender();
    removeItem(obj);
}

void QObjectListModel::removeItem(QObject *item)
{
    int index = _list->indexOf(item);
    if (index >= 0) {
        beginRemoveRows(QModelIndex(), index, index);
        _list->removeAt(index);
        disconnect(item, &QObject::destroyed,
                   this, &QObjectListModel::removeDestroyedItem);
        endRemoveRows();
        emit itemRemoved(item);
        emit itemCountChanged();
    }
}

void QObjectListModel::removeItems(const QList<QObject *> &items)
{
    QList<QPair<int, QObject *> > removals;
    foreach (QObject *item, items) {
        int index = _list->indexOf(item);
        if (index != -1) {
            removals.append(qMakePair(index, item));
        }
    }

    if (!removals.isEmpty()) {
        struct Comparator {
            bool operator()(const QPair<int, QObject *> &lhs, const QPair<int, QObject *> &rhs) const {
                return lhs.first < rhs.first;
            }
        } cmp;
        std::sort(removals.begin(), removals.end(), cmp);

        int count(removals.count());
        while (count > 0) {
            // Find any contiguous runs of removal indexes to be processed together
            int last = count - 1;
            int first = last;
            while (first > 0 && removals.at(first - 1).first == (removals.at(first).first - 1)) {
                --first;
            }

            beginRemoveRows(QModelIndex(), removals.at(first).first, removals.at(last).first);
            while (last >= first) {
                const QPair<int, QObject *> &removal(removals.at(last));
                --last;

                _list->removeAt(removal.first);
                disconnect(removal.second, &QObject::destroyed,
                           this, &QObjectListModel::removeDestroyedItem);
            }
            endRemoveRows();

            count = first;
        }

        QList<QPair<int, QObject *> >::const_iterator it = removals.constBegin(), end = removals.constEnd();
        for ( ; it != end; ++it) {
            emit itemRemoved(it->second);
        }

        emit itemCountChanged();
    }
}

void QObjectListModel::removeItem(int index)
{
    beginRemoveRows(QModelIndex(), index, index);
    disconnect(((QObject*)_list->at(index)), &QObject::destroyed,
               this, &QObjectListModel::removeDestroyedItem);
    QObject *item = _list->takeAt(index);
    endRemoveRows();
    emit itemRemoved(item);
    emit itemCountChanged();
}

QObject* QObjectListModel::get(int index)
{
    if (index >= _list->count() || index < 0)
        return 0;

    QObject *obj(_list->at(index));
    QQmlEngine::setObjectOwnership(obj, QQmlEngine::CppOwnership);
    return obj;
}

QList<QObject*> *QObjectListModel::getList()
{
    return _list;
}

void QObjectListModel::setList(QList<QObject *> *list)
{
    QList<QObject *> *oldList = _list;
    beginResetModel();
    _list = list;
    endResetModel();
    emit itemCountChanged();
    delete oldList;
}

void QObjectListModel::synchronizeList(const QList<QObject *> &list)
{
    ::synchronizeList(this, *_list, list);

    // Report addition/removals after synch completes, because a move may cause an
    // item to be both removed and added transiently
    foreach (QObject *item, _inserted) {
        emit itemAdded(item);
    }
    foreach (QObject *item, _removed) {
        emit itemRemoved(item);
    }

    if (!_inserted.isEmpty() || !_removed.isEmpty()) {
        emit itemCountChanged();
    }

    _inserted.clear();
    _removed.clear();
}

int QObjectListModel::insertRange(int index, int count, const QList<QObject *> &source, int sourceIndex)
{
    const int end = index + count - 1;
    beginInsertRows(QModelIndex(), index, end);

    for (int i = 0; i < count; ++i) {
        QObject *item(source.at(sourceIndex + i));
        _list->insert(index + i, item);
        int removedIndex = _removed.indexOf(item);
        if (removedIndex != -1) {
            _removed.removeAt(removedIndex);
        } else {
            _inserted.append(item);
        }
    }

    endInsertRows();
    return end - index + 1;
}

int QObjectListModel::removeRange(int index, int count)
{
    const int end = index + count - 1;
    beginRemoveRows(QModelIndex(), index, end);

    for (int i = 0; i < count; ++i) {
        QObject *item(_list->at(index));
        int insertedIndex = _inserted.indexOf(item);
        if (insertedIndex != -1) {
            _inserted.removeAt(insertedIndex);
        } else {
            _removed.append(item);
        }
        _list->removeAt(index);
    }

    endRemoveRows();
    return 0;
}

void QObjectListModel::reset()
{
    setList(new QList<QObject*>());
}

void QObjectListModel::move(int oldRow, int newRow)
{
    if (oldRow < 0 || oldRow >= _list->count())
        return;

    if (newRow < 0 || newRow >= _list->count())
        return;

    beginMoveRows(QModelIndex(), oldRow, oldRow, QModelIndex(), (newRow > oldRow) ? (newRow + 1) : newRow);
    _list->move(oldRow, newRow);
    endMoveRows();
}

void QObjectListModel::update(int row)
{
    if (row < 0 || row >= _list->count())
        return;

    const QModelIndex changeIndex(index(row, 0));
    emit dataChanged(changeIndex, changeIndex);
}
