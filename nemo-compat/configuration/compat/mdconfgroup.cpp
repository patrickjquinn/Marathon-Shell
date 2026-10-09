// SPDX-FileCopyrightText: 2014 Jolla Mobile
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-only
/***************************************************************************
** Copyright (C) 2014 Jolla Mobile <andrew.den.exter@jollamobile.com>
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/
/*
 * Keel: adapted from mlite's src/mdconfgroup.cpp (github.com/sailfishos/mlite,
 * commit 42c3b2102dadfc54a2cc7c87c6e4cfb28437c908) for hosts without
 * mlite-qt6. The property binding, scope and path resolution follow mlite;
 * the DConfClient (watch/read/write, GLib signal) is replaced by Keel's
 * KeelDConfStore, so every group listens to the store directly instead of
 * being notified through its parent scope. Device builds link the real
 * mlite-qt6 and do not compile this file.
 */

#include "mdconfgroup.h"
#include "keeldconfstore.h"

#include <QMetaProperty>

class MDConfGroupPrivate : public QObject
{
public:
    void readValue(const QMetaProperty &property);
    void resolveProperties(const QString &scopePath);
    void cancelNotifications();
    void keyChanged(const QString &absoluteKey);

    QString absolutePath; // ends with '/' once resolved, empty otherwise
    QString path;
    QList<MDConfGroup *> children;
    MDConfGroup *group = nullptr;
    MDConfGroup *scope = nullptr;
    QMetaObject::Connection storeConnection;

    int notifyIndex = -1;
    int propertyOffset = -1;
    bool synchronous = false;
};

MDConfGroup::MDConfGroup(QObject *parent, BindOption option)
    : QObject(parent)
    , priv(new MDConfGroupPrivate)
{
    priv->group = this;
    if (option == DontBindProperties)
        resolveMetaObject(metaObject()->propertyCount());
}

MDConfGroup::MDConfGroup(const QString &path, QObject *parent, BindOption option)
    : QObject(parent)
    , priv(new MDConfGroupPrivate)
{
    priv->group = this;
    priv->path = path;
    if (option == DontBindProperties)
        resolveMetaObject(metaObject()->propertyCount());
}

MDConfGroup::~MDConfGroup()
{
    priv->cancelNotifications();
    for (MDConfGroup *child : std::as_const(priv->children))
        child->priv->scope = nullptr;
    if (priv->scope)
        priv->scope->priv->children.removeAll(this);
}

void MDConfGroup::resolveMetaObject(int propertyOffset)
{
    if (priv->propertyOffset >= 0)
        return;

    const int propertyChangedIndex = staticMetaObject.indexOfMethod("propertyChanged()");
    Q_ASSERT(propertyChangedIndex != -1);

    const QMetaObject *const metaObject = this->metaObject();
    if (propertyOffset < 0)
        propertyOffset = staticMetaObject.propertyCount();
    priv->propertyOffset = propertyOffset;

    for (int i = propertyOffset; i < metaObject->propertyCount(); ++i) {
        const QMetaProperty property = metaObject->property(i);
        if (property.hasNotifySignal()) {
            QMetaObject::connect(this, property.notifySignalIndex(),
                                 this, propertyChangedIndex, Qt::UniqueConnection);
        }
    }

    if (priv->path.startsWith(QLatin1Char('/')))
        priv->resolveProperties(QString());
    else if (priv->scope && !priv->path.isEmpty() && !priv->scope->priv->absolutePath.isEmpty())
        priv->resolveProperties(priv->scope->priv->absolutePath);
}

QString MDConfGroup::path() const
{
    return priv->path;
}

void MDConfGroup::setPath(const QString &path)
{
    if (priv->path == path)
        return;

    priv->cancelNotifications();
    priv->path = path;
    emit pathChanged();

    if (priv->path.isEmpty() || priv->propertyOffset < 0)
        return;
    if (priv->path.startsWith(QLatin1Char('/')))
        priv->resolveProperties(QString());
    else if (priv->scope && !priv->scope->priv->absolutePath.isEmpty())
        priv->resolveProperties(priv->scope->priv->absolutePath);
}

MDConfGroup *MDConfGroup::scope() const
{
    return priv->scope;
}

void MDConfGroup::setScope(MDConfGroup *scope)
{
    if (scope == priv->scope)
        return;

    const bool isAbsolute = priv->path.startsWith(QLatin1Char('/'));
    if (priv->scope)
        priv->scope->priv->children.removeAll(this);
    if (!isAbsolute)
        priv->cancelNotifications();

    priv->scope = scope;
    if (priv->scope) {
        priv->scope->priv->children.append(this);
        if (!priv->path.isEmpty() && !isAbsolute && priv->propertyOffset >= 0
                && !priv->scope->priv->absolutePath.isEmpty()) {
            priv->resolveProperties(priv->scope->priv->absolutePath);
        }
    }
    emit scopeChanged();
}

bool MDConfGroup::isSynchronous() const
{
    return priv->synchronous;
}

void MDConfGroup::setSynchronous(bool synchronous)
{
    // The fallback store writes through on every change, so both modes behave
    // like dconf's synchronous API.
    if (priv->synchronous != synchronous) {
        priv->synchronous = synchronous;
        emit synchronousChanged();
    }
}

QVariant MDConfGroup::value(const QString &key, const QVariant &defaultValue, int typeHint) const
{
    if (priv->absolutePath.isEmpty() || key.isEmpty())
        return defaultValue;
    const QString absoluteKey = key.startsWith(QLatin1Char('/')) ? key : priv->absolutePath + key;
    const QVariant value = KeelDConfStore::instance()->read(absoluteKey, typeHint);
    return value.isValid() ? value : defaultValue;
}

void MDConfGroup::setValue(const QString &key, const QVariant &value)
{
    if (priv->absolutePath.isEmpty() || key.isEmpty())
        return;
    const QString absoluteKey = key.startsWith(QLatin1Char('/')) ? key : priv->absolutePath + key;
    KeelDConfStore::instance()->write(absoluteKey, value);
}

void MDConfGroup::clear()
{
    if (!priv->absolutePath.isEmpty())
        KeelDConfStore::instance()->clear(priv->absolutePath);
}

void MDConfGroup::sync()
{
    KeelDConfStore::instance()->sync();
}

void MDConfGroup::propertyChanged()
{
    const int notifyIndex = senderSignalIndex();
    if (priv->absolutePath.isEmpty() || notifyIndex == priv->notifyIndex)
        return;

    const QMetaObject *const metaObject = this->metaObject();
    for (int i = priv->propertyOffset; i < metaObject->propertyCount(); ++i) {
        const QMetaProperty property = metaObject->property(i);
        if (property.notifySignalIndex() == notifyIndex) {
            KeelDConfStore::instance()->write(
                    priv->absolutePath + QString::fromLatin1(property.name()),
                    property.read(this));
        }
    }
}

void MDConfGroupPrivate::readValue(const QMetaProperty &property)
{
    const QVariant value = KeelDConfStore::instance()->read(
            absolutePath + QString::fromLatin1(property.name()), property.userType());
    if (value.isValid()) {
        // Mark the notify signal so propertyChanged() does not write back.
        notifyIndex = property.notifySignalIndex();
        property.write(group, value);
        notifyIndex = -1;
    }
}

void MDConfGroupPrivate::resolveProperties(const QString &scopePath)
{
    absolutePath = scopePath + path + QLatin1Char('/');

    const QMetaObject *const metaObject = group->metaObject();
    for (int i = propertyOffset; i < metaObject->propertyCount(); ++i)
        readValue(metaObject->property(i));

    QObject::disconnect(storeConnection);
    storeConnection = QObject::connect(KeelDConfStore::instance(), &KeelDConfStore::keyChanged,
                                       this, &MDConfGroupPrivate::keyChanged);

    for (MDConfGroup *child : std::as_const(children)) {
        if (child->priv->absolutePath.isEmpty() && child->priv->propertyOffset >= 0
                && !child->priv->path.isEmpty()
                && !child->priv->path.startsWith(QLatin1Char('/'))) {
            child->priv->resolveProperties(absolutePath);
        }
    }
}

void MDConfGroupPrivate::cancelNotifications()
{
    if (absolutePath.isEmpty())
        return;
    QObject::disconnect(storeConnection);
    absolutePath.clear();
    for (MDConfGroup *child : std::as_const(children)) {
        if (!child->priv->path.startsWith(QLatin1Char('/')))
            child->priv->cancelNotifications();
    }
}

void MDConfGroupPrivate::keyChanged(const QString &absoluteKey)
{
    if (absolutePath.isEmpty() || !absoluteKey.startsWith(absolutePath))
        return;
    const QString key = absoluteKey.mid(absolutePath.size());
    if (key.contains(QLatin1Char('/')))
        return; // a key of a sub-directory; child groups listen themselves

    const QMetaObject *const metaObject = group->metaObject();
    const int propertyIndex = metaObject->indexOfProperty(key.toLatin1().constData());
    if (propertyIndex >= propertyOffset && propertyOffset >= 0)
        readValue(metaObject->property(propertyIndex));
    emit group->valueChanged(key);
}
