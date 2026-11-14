// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's fallback MDConfItem over KeelDConfStore, for hosts without
// mlite-qt6. Implements the API declared in mlite's mdconfitem.h (kept
// unchanged next to this file); written for Keel, not copied from mlite.

#include "mdconfitem.h"
#include "keeldconfstore.h"

struct MDConfItemPrivate
{
    QString key;
    QVariant value;
};

MDConfItem::MDConfItem(const QString &key, QObject *parent)
    : QObject(parent)
    , priv(new MDConfItemPrivate)
{
    priv->key = key;
    KeelDConfStore *store = KeelDConfStore::instance();
    connect(store, &KeelDConfStore::keyChanged, this, [this](const QString &changed) {
        if (changed == priv->key)
            update_value(true);
    });
    update_value(false);
}

MDConfItem::~MDConfItem()
{
    delete priv;
}

QString MDConfItem::key() const
{
    return priv->key;
}

QVariant MDConfItem::value() const
{
    return priv->value;
}

QVariant MDConfItem::value(const QVariant &def) const
{
    return priv->value.isValid() ? priv->value : def;
}

void MDConfItem::set(const QVariant &val)
{
    // The store emits keyChanged(), which updates the cached value and emits
    // valueChanged() synchronously, as mlite does for the calling item.
    KeelDConfStore::instance()->write(priv->key, val);
}

void MDConfItem::unset()
{
    set(QVariant());
}

QStringList MDConfItem::listDirs() const
{
    return KeelDConfStore::instance()->listDirs(priv->key);
}

bool MDConfItem::sync()
{
    return KeelDConfStore::instance()->sync();
}

void MDConfItem::update_value(bool emit_signal)
{
    const QVariant fresh = KeelDConfStore::instance()->read(priv->key);
    if (fresh == priv->value && fresh.isValid() == priv->value.isValid())
        return;
    priv->value = fresh;
    if (emit_signal)
        emit valueChanged();
}
