// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: Sailfish.WebView.Controls reaches the WebEngine singleton
// (Keel's Sailfish.WebEngine plugin, another library) through the QML engine
// instead of SailfishOS::WebEngine::instance().

#ifndef KEEL_WEBENGINELINK_H
#define KEEL_WEBENGINELINK_H

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QVariant>

namespace KeelWebEngineLink {

inline QPointer<QObject> &webEngine()
{
    static QPointer<QObject> instance;
    return instance;
}

// The engine's Sailfish.WebEngine WebEngine singleton.
inline QObject *instance(QQmlEngine *engine = nullptr)
{
    if (!webEngine() && engine) {
        const int id = qmlTypeId("Sailfish.WebEngine", 1, 0, "WebEngine");
        if (id >= 0)
            webEngine() = engine->singletonInstance<QObject *>(id);
    }
    return webEngine();
}

inline void addObserver(const QString &topic)
{
    if (QObject *o = instance())
        QMetaObject::invokeMethod(o, "addObserver", Q_ARG(QString, topic));
}

inline void notifyObservers(const QString &topic, const QVariant &value)
{
    if (QObject *o = instance())
        QMetaObject::invokeMethod(o, "notifyObservers", Q_ARG(QString, topic), Q_ARG(QVariant, value));
}

} // namespace KeelWebEngineLink

#endif // KEEL_WEBENGINELINK_H
