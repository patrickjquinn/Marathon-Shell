// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "enterkey.h"

#include <QGuiApplication>
#include <QInputMethod>
#include <QHash>
#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlProperty>
#include <QQuickItem>
#include <QTimer>

KeelEnterKeyAttached::KeelEnterKeyAttached(QObject *parent)
    : QObject(parent)
{
    if (auto *item = qobject_cast<QQuickItem *>(parent)) {
        connect(item, &QQuickItem::windowChanged, this, &KeelEnterKeyAttached::watchWindow);
        // The attachee's editor exists once it is complete.
        QTimer::singleShot(0, this, [this] {
            watchWindow();
            updateInputMethod();
        });
    }
}

void KeelEnterKeyAttached::watchWindow()
{
    auto *item = qobject_cast<QQuickItem *>(parent());
    QQuickWindow *w = item ? item->window() : nullptr;
    if (w == m_window)
        return;
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = w;
    if (m_window)
        m_window->installEventFilter(this);
}

bool KeelEnterKeyAttached::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_window || event->type() != QEvent::KeyPress || !m_enabled)
        return false;
    auto *ke = static_cast<QKeyEvent *>(event);
    if (ke->key() != Qt::Key_Return && ke->key() != Qt::Key_Enter)
        return false;
    auto *item = qobject_cast<QQuickItem *>(parent());
    QQuickItem *focus = m_window->activeFocusItem();
    if (!item || !focus || (focus != item && !item->isAncestorOf(focus)))
        return false;
    emit clicked();
    // A multi-line editor (TextArea) still gets its new line.
    return !focus->inherits("QQuickTextEdit");
}

void KeelEnterKeyAttached::setEnabled(bool v)
{
    if (v == m_enabled)
        return;
    m_enabled = v;
    emit enabledChanged();
    updateInputMethod();
}

void KeelEnterKeyAttached::setHighlighted(bool v)
{
    if (v == m_highlighted)
        return;
    m_highlighted = v;
    emit highlightedChanged();
    updateInputMethod();
}

void KeelEnterKeyAttached::setIconSource(const QUrl &v)
{
    if (v == m_iconSource)
        return;
    m_iconSource = v;
    emit iconSourceChanged();
    updateInputMethod();
}

void KeelEnterKeyAttached::setText(const QString &v)
{
    if (v == m_text)
        return;
    m_text = v;
    emit textChanged();
    updateInputMethod();
}

int KeelEnterKeyAttached::enterKeyType() const
{
    // The documented theme icons map onto Qt's enter key types.
    const QString icon = m_iconSource.toString();
    if (icon.endsWith(QLatin1String("icon-m-enter-next")))
        return Qt::EnterKeyNext;
    if (icon.endsWith(QLatin1String("icon-m-enter-close")))
        return Qt::EnterKeyDone;
    if (icon.endsWith(QLatin1String("icon-m-enter-accept")))
        return Qt::EnterKeyGo;
    return Qt::EnterKeyDefault;
}

// A context whose only import is Qt Quick, so that "EnterKey" names Qt
// Quick's attached type (a Silica import would make it Silica's).
static QQmlContext *qtQuickContext(QQmlEngine *engine)
{
    static QHash<QQmlEngine *, QPointer<QObject>> holders;
    QPointer<QObject> &holder = holders[engine];
    if (!holder) {
        QQmlComponent component(engine);
        component.setData("import QtQuick 2.6\nQtObject {}", QUrl(QStringLiteral("qrc:/keel/enterkey.qml")));
        if (component.isReady())
            holder = component.create();
        if (holder)
            holder->setParent(engine);
    }
    return holder ? qmlContext(holder) : nullptr;
}

void KeelEnterKeyAttached::updateInputMethod()
{
    auto *item = qobject_cast<QQuickItem *>(parent());
    if (!item)
        return;
    // Qt Quick's EnterKey.type on the editor of a Silica text field.
    auto *editor = item->property("_editor").value<QQuickItem *>();
    QQmlEngine *engine = qmlEngine(item);
    if (QQmlContext *context = engine ? qtQuickContext(engine) : nullptr; editor && context) {
        QQmlProperty type(editor, QStringLiteral("EnterKey.type"), context);
        if (type.isValid())
            type.write(enterKeyType());
    }
    // Ask the input method to re-query the focused item.
    if (item->hasActiveFocus())
        QGuiApplication::inputMethod()->update(Qt::ImEnterKeyType);
}

KeelEnterKeyAttached *KeelEnterKey::qmlAttachedProperties(QObject *object)
{
    return new KeelEnterKeyAttached(object);
}

KeelEnterKeyAttached *KeelEnterKeyHelper::attachedTo(QObject *item) const
{
    if (!item)
        return nullptr;
    return qobject_cast<KeelEnterKeyAttached *>(qmlAttachedPropertiesObject<KeelEnterKey>(item, true));
}
