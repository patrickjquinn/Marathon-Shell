// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see silicatext.h.

#include "silicatext.h"

#include "keeltheme.h"
#include "palette.h"

#include <QHash>
#include <QMetaProperty>
#include <QQmlContext>
#include <QQmlEngine>

namespace {

// Index of `name` in the class of `object` (-1: none), looked up once per
// class.
int propertyIndex(const QObject *object, const char *name)
{
    static QHash<QPair<const QMetaObject *, const char *>, int> indexes;
    const QMetaObject *mo = object->metaObject();
    const auto key = qMakePair(mo, name);
    auto it = indexes.constFind(key);
    if (it == indexes.constEnd())
        it = indexes.insert(key, mo->indexOfProperty(name));
    return *it;
}

// What `__silica_applicationwindow_instance` names where `object` was
// created: an ApplicationWindow's property of that name (the context object
// of its file, or of a file within it), else the engine's context property
// (windowdefaults.h, set on the root context).
QObject *windowInstance(const QObject *object)
{
    static const char name[] = "__silica_applicationwindow_instance";
    QQmlContext *ctx = qmlContext(object);
    for (; ctx; ctx = ctx->parentContext()) {
        if (QObject *scope = ctx->contextObject()) {
            const int index = propertyIndex(scope, name);
            if (index >= 0)
                return scope->metaObject()->property(index).read(scope).value<QObject *>();
        }
        if (!ctx->parentContext())
            return ctx->contextProperty(QLatin1String(name)).value<QObject *>();
    }
    return nullptr;
}

} // namespace

KeelSilicaText::KeelSilicaText(QQuickItem *parent)
    : QQuickText(parent)
    , m_palette(new KeelPalette(this))
{
    connect(m_palette, &KeelPalette::parentHighlightedChanged, this, [this] {
        if (!m_highlightedSet)
            emit highlightedChanged();
    });
    connect(m_palette, &KeelPalette::changed, this, &KeelSilicaText::followPalette);
}

bool KeelSilicaText::highlighted() const
{
    return m_highlightedSet ? m_highlighted : m_palette->parentHighlighted();
}

void KeelSilicaText::setHighlighted(bool highlighted)
{
    const bool old = this->highlighted();
    m_highlightedSet = true;
    m_highlighted = highlighted;
    if (old != highlighted)
        emit highlightedChanged();
}

void KeelSilicaText::resetHighlighted()
{
    const bool old = highlighted();
    m_highlightedSet = false;
    if (old != highlighted())
        emit highlightedChanged();
}

void KeelSilicaText::classBegin()
{
    QQuickText::classBegin();
    // Before the item's own bindings: the defaults are in place when they
    // are first evaluated, and the app's values replace them.
    m_palette->classBegin();
    m_theme = keel::theme(this);
    if (m_theme) {
        // By index, once per class: a connection by name parses both
        // signatures on every call.
        static const int signal = m_theme->metaObject()->indexOfSignal("fontFamilyChanged()");
        static const int slot = staticMetaObject.indexOfSlot("followThemeFont()");
        if (signal >= 0)
            QMetaObject::connect(m_theme, signal, this, slot);
    }
    followThemeFont();
    followPalette();
    readDefaultLabelFormat();
}

void KeelSilicaText::componentComplete()
{
    m_palette->componentComplete();
    QQuickText::componentComplete();
}

void KeelSilicaText::followThemeFont()
{
    const int index = m_theme ? propertyIndex(m_theme, "fontFamily") : -1;
    const QString family = index >= 0 ? m_theme->metaObject()->property(index).read(m_theme).toString() : QString();
    if (family.isEmpty() || family == m_themeFamily)
        return;
    QFont f = font();
    const bool ours = m_themeFamily.isEmpty() || f.family() == m_themeFamily;
    m_themeFamily = family;
    if (ours) {
        f.setFamily(family);
        setFont(f);
    }
}

void KeelSilicaText::followPalette()
{
    const QColor c = m_palette->highlightColor();
    if (c == m_paletteLinkColor)
        return;
    const bool ours = !m_paletteLinkColor.isValid() || linkColor() == m_paletteLinkColor;
    m_paletteLinkColor = c;
    if (ours)
        setLinkColor(c);
}

void KeelSilicaText::readDefaultLabelFormat()
{
    QObject *window = windowInstance(this);
    if (window != m_window) {
        disconnect(m_windowConnection);
        m_window = window;
        if (window) {
            const int index = propertyIndex(window, "_defaultLabelFormat");
            const QMetaProperty p = index >= 0 ? window->metaObject()->property(index) : QMetaProperty();
            if (p.hasNotifySignal()) {
                static const int slot = staticMetaObject.indexOfMethod("readDefaultLabelFormat()");
                m_windowConnection = QMetaObject::connect(window, p.notifySignalIndex(), this, slot);
            }
        }
    }
    int format = QQuickText::AutoText;
    if (m_window) {
        const int index = propertyIndex(m_window, "_defaultLabelFormat");
        if (index >= 0)
            format = m_window->metaObject()->property(index).read(m_window).toInt();
    }
    if (format != m_defaultLabelFormat) {
        m_defaultLabelFormat = format;
        emit defaultLabelFormatChanged();
    }
}
