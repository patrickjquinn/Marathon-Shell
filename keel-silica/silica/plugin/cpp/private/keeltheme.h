// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Access to Keel's Theme singleton (Keel.SilicaCore, re-exported by
// Sailfish.Silica; plugin/cpp/theme.h) from the native types, for sizes
// such as itemSizeExtraSmall and startDragDistance.
#ifndef KEEL_KEELTHEME_H
#define KEEL_KEELTHEME_H

#include <QObject>
#include <QQmlEngine>
#include <QVariant>

namespace keel {

// The Theme object, found once per engine and kept on it. Touch handlers
// read Theme sizes on every move, and qmlTypeId() builds a whole temporary
// QQmlEngine to resolve a type it has not registered: looked up every time,
// that was a third of a scrolling app's main thread.
inline QObject *theme(const QObject *context)
{
    QQmlEngine *engine = context ? qmlEngine(context) : nullptr;
    if (!engine)
        return nullptr;
    static const char key[] = "_keel_theme";
    const QVariant cached = engine->property(key);
    if (cached.isValid())
        return cached.value<QObject *>();
    QObject *t = nullptr;
    static const int id = qmlTypeId("Keel.SilicaCore", 1, 0, "Theme");
    if (id >= 0)
        t = engine->singletonInstance<QObject *>(id);
    // Not cached when not found (an engine that has not loaded the module).
    if (t)
        engine->setProperty(key, QVariant::fromValue(t));
    return t;
}

// Theme.<name>, or fallback when there is no Theme or no such property.
inline qreal themeValue(const QObject *context, const char *name, qreal fallback)
{
    QObject *t = theme(context);
    const QVariant v = t ? t->property(name) : QVariant();
    return v.isValid() && v.canConvert<qreal>() ? v.toReal() : fallback;
}

} // namespace keel

#endif // KEEL_KEELTHEME_H
