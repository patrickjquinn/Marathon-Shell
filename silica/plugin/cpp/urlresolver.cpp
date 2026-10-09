// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "urlresolver.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QVariant>

QUrl KeelUrlResolver::resolve(const QUrl &url, QObject *contextObject) const
{
    if (url.isEmpty() || !url.isRelative() || !contextObject)
        return url;
    QQmlContext *context = qmlContext(contextObject);
    return context ? context->resolvedUrl(url) : url;
}

void KeelUrlResolver::fixSource(QObject *target, QObject *contextObject, const QString &property) const
{
    if (!target)
        return;
    const QByteArray name = property.toLatin1();
    const QUrl current = target->property(name.constData()).toUrl();
    if (current.isEmpty() || !current.isRelative())
        return;
    const QUrl resolved = resolve(current, contextObject);
    if (resolved != current)
        target->setProperty(name.constData(), resolved);
}

void KeelUrlResolver::fixSourceForControl(QObject *target, const QString &property) const
{
    if (!target)
        return;
    static const QString keelPrefix = QStringLiteral("qrc:/qt/qml/Sailfish/");
    for (QObject *o = target; o;) {
        QQmlContext *context = qmlContext(o);
        if (context && !context->baseUrl().toString().startsWith(keelPrefix)) {
            fixSource(target, o, property);
            return;
        }
        auto *item = qobject_cast<QQuickItem *>(o);
        o = item && item->parentItem() ? item->parentItem() : o->parent();
    }
}
