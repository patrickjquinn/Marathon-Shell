// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "mediakey.h"

#include <QGuiApplication>
#include <QKeyEvent>
#include <QPlatformSurfaceEvent>
#include <QWindow>
#include <algorithm>
#include <qpa/qplatformnativeinterface.h>

MediaKey::MediaKey(QObject *parent)
    : QObject(parent)
{
}

MediaKey::~MediaKey()
{
    MediaKeyRegistry::instance()->remove(this);
}

void MediaKey::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    if (!enabled)
        setPressed(false);
    emit enabledChanged();
    if (m_complete)
        MediaKeyRegistry::instance()->update();
}

void MediaKey::setKey(int key)
{
    if (m_key == key)
        return;
    m_key = key;
    setPressed(false);
    emit keyChanged();
    if (m_complete)
        MediaKeyRegistry::instance()->update();
}

void MediaKey::componentComplete()
{
    m_complete = true;
    MediaKeyRegistry::instance()->add(this);
}

void MediaKey::setPressed(bool pressed)
{
    if (m_pressed == pressed)
        return;
    m_pressed = pressed;
    emit pressedChanged();
}

void MediaKey::handlePress(bool autoRepeat)
{
    if (autoRepeat && m_pressed) {
        emit repeat();
        return;
    }
    if (m_pressed)
        return;
    setPressed(true);
    emit pressed();
}

void MediaKey::handleRelease()
{
    if (!m_pressed)
        return;
    setPressed(false);
    emit released();
}

MediaKeyRegistry::MediaKeyRegistry() = default;

MediaKeyRegistry *MediaKeyRegistry::instance()
{
    // Lives as long as the application; parented so it goes with it.
    static QPointer<MediaKeyRegistry> registry;
    if (!registry) {
        registry = new MediaKeyRegistry;
        registry->setParent(QCoreApplication::instance());
    }
    return registry;
}

void MediaKeyRegistry::add(MediaKey *key)
{
    m_keys.append(key);
    update();
}

void MediaKeyRegistry::remove(MediaKey *key)
{
    m_keys.removeAll(key);
    m_keys.removeAll(nullptr);
    update();
}

void MediaKeyRegistry::update()
{
    QList<int> codes;
    for (const QPointer<MediaKey> &k : std::as_const(m_keys)) {
        if (k && k->isEnabled() && k->key() != 0 && !codes.contains(k->key()))
            codes.append(k->key());
    }
    std::sort(codes.begin(), codes.end());
    QStringList grabbed;
    grabbed.reserve(codes.size());
    for (int c : std::as_const(codes))
        grabbed.append(QString::number(c));

    // The filter stays installed while any MediaKey exists, also to see new
    // platform windows; it only takes events while keys are grabbed.
    const bool filter = !m_keys.isEmpty();
    if (filter != m_filtering && QCoreApplication::instance()) {
        if (filter)
            QCoreApplication::instance()->installEventFilter(this);
        else
            QCoreApplication::instance()->removeEventFilter(this);
        m_filtering = filter;
    }
    if (grabbed != m_grabbed) {
        m_grabbed = grabbed;
        applyToAll();
    }
}

void MediaKeyRegistry::applyTo(QWindow *window) const
{
    const QVariant value(m_grabbed);
    window->setProperty(propertyName(), value);
    if (QPlatformWindow *handle = window->handle()) {
        if (QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface())
            native->setWindowProperty(handle, QString::fromLatin1(propertyName()), value);
    }
}

void MediaKeyRegistry::applyToAll() const
{
    if (!qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
        return;
    const QWindowList windows = QGuiApplication::topLevelWindows();
    for (QWindow *w : windows)
        applyTo(w);
}

bool MediaKeyRegistry::eventFilter(QObject *watched, QEvent *event)
{
    switch (event->type()) {
    case QEvent::PlatformSurface:
        // A window got its platform surface: give it the current grab (an
        // app window is usually created after its MediaKeys).
        if (auto *window = qobject_cast<QWindow *>(watched)) {
            if (static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType()
                    == QPlatformSurfaceEvent::SurfaceCreated
                && !window->parent())
                applyTo(window);
        }
        return false;
    case QEvent::KeyPress:
    case QEvent::KeyRelease: {
        // Key events reach the window first and the items from there; take
        // them at the window, once.
        if (m_grabbed.isEmpty() || !watched->isWindowType())
            return false;
        auto *ke = static_cast<QKeyEvent *>(event);
        bool taken = false;
        // Copy: a handler may destroy or disable MediaKeys.
        const QList<QPointer<MediaKey>> keys = m_keys;
        for (const QPointer<MediaKey> &k : keys) {
            if (!k || !k->grabs(ke->key()))
                continue;
            taken = true;
            if (event->type() == QEvent::KeyPress)
                k->handlePress(ke->isAutoRepeat());
            else if (!ke->isAutoRepeat())
                k->handleRelease();
        }
        return taken;
    }
    default:
        return false;
    }
}
