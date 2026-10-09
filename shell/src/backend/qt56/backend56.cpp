/****************************************************************************
**
** SPDX-FileCopyrightText: 2012 Digia Plc and/or its subsidiary(-ies).
** SPDX-FileCopyrightText: 2017-2020 Elros https://github.com/elros34
** SPDX-FileCopyrightText: 2020-2023 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from qt-runner src/qmlcompositor.cpp and qml/WindowContainer.qml
** (BSD-3-Clause). Full licence text in backend56.h and upstream-licenses/.
** See PROVENANCE.md.
**
****************************************************************************/

#include "backend56.h"

#include <QDebug>
#include <QGuiApplication>
#include <QQuickItem>
#include <QScreen>

#include <QtCompositor/QWaylandOutput>
#include <QtCompositor/QWaylandQuickSurface>
#include <QtCompositor/QWaylandSurface>
#include <QtCompositor/QWaylandSurfaceItem>
#include <QtCompositor/QWaylandInputDevice>
#include <QtCompositor/private/qwloutput_p.h>
#include <QtCompositor/private/qwlsurface_p.h>

#include "../../core/graphics.h"
#include "../../core/shellstate.h"

namespace keel {

Compositor56::Compositor56(Backend56 *backend, const QByteArray &socketName)
    : QObject(backend)
    , QWaylandQuickCompositor(socketName.constData(), DefaultExtensions | SubSurfaceExtension)
    , m_backend(backend)
{
    addDefaultShell();
}

QWaylandOutput *Compositor56::addOutput(QQuickWindow *window)
{
    return createOutput(window, QStringLiteral("Shipwright"), QStringLiteral("keel-shell"));
}

void Compositor56::surfaceCreated(QWaylandSurface *surface)
{
    m_backend->onSurfaceCreated(surface);
}

OuterWindow56::OuterWindow56(Backend56 *backend, int windowId, WindowRole role)
    : m_backend(backend)
    , m_windowId(windowId)
    , m_role(role)
{
    // Translucent like Silica windows: Lipstick composes the ambience
    // wallpaper underneath (see LipstickWindow::prepare for the alpha format).
    setColor(Qt::transparent);
}

void OuterWindow56::resizeEvent(QResizeEvent *event)
{
    QQuickWindow::resizeEvent(event);
    if (m_output)
        m_output->setGeometry(QRect(QPoint(0, 0), size()));
    layoutItems();
}

void OuterWindow56::layoutItems()
{
    WindowMapper *mapper = m_backend->mapper();
    const SurfaceKey primary = mapper->primarySurface(m_windowId);
    int z = 0;
    for (SurfaceKey key : mapper->surfacesInWindow(m_windowId)) {
        QWaylandSurface *surface = m_backend->surfaceForKey(key);
        QWaylandSurfaceItem *item = m_backend->itemFor(surface);
        if (!surface || !item)
            continue;
        const SurfaceInfo info = mapper->surfaceInfo(key);
        if (info.kind == SurfaceKind::SubSurface)
            continue;   // QtCompositor parents subsurface items to their parent item
        item->setParentItem(contentItem());
        item->setZ(++z);
        item->setTouchEventsEnabled(true);
        if (key == primary && m_role != WindowRole::Cover) {
            int height = this->height();
            if (m_role == WindowRole::Main)
                height = qMax(1, height - m_backend->keyboardHeight());
            item->setResizeSurfaceToItem(true);
            item->setPosition(QPointF(0, 0));
            item->setSize(QSizeF(width(), height));
        } else if (key == primary) {
            // Cover: the client picks the size; the Lipstick window follows.
            item->setResizeSurfaceToItem(false);
            item->setPosition(QPointF(0, 0));
            item->setSize(surface->size());
            if (!surface->size().isEmpty() && surface->size() != size())
                resize(surface->size());
        } else {
            // Transient or popup: place relative to its parent (qt-runner
            // centred all extra surfaces; wl_shell gives us the offset).
            QPointF pos;
            QWaylandSurface *parent = m_backend->surfaceForKey(info.parent);
            QWaylandSurfaceItem *parentItem = m_backend->itemFor(parent);
            if (parentItem && parentItem->window() == this)
                pos = parentItem->position() + surface->transientOffset();
            else
                pos = QPointF((width() - surface->size().width()) / 2.0,
                              (height() - surface->size().height()) / 2.0);
            item->setResizeSurfaceToItem(false);
            item->setPosition(pos);
            item->setSize(surface->size());
        }
    }
}

Backend56::Backend56(ShellState *state, QObject *parent)
    : Backend(state, parent)
{
    connect(mapper(), &WindowMapper::windowCreated, this, &Backend56::onWindowCreated);
    connect(mapper(), &WindowMapper::windowDestroyed, this, &Backend56::onWindowDestroyed);
    connect(mapper(), &WindowMapper::surfaceAssigned, this, &Backend56::onSurfaceAssigned);
    connect(mapper(), &WindowMapper::surfaceRemoved, this, &Backend56::onSurfaceRemoved);
    connect(state, &ShellState::keyboardRectChanged, this, &Backend56::onKeyboardRectChanged);
}

Backend56::~Backend56()
{
    // Destroy clients before their outputs' windows go away.
    if (m_compositor) {
        const QList<QWaylandSurface *> surfaces = m_compositor->surfaces();
        for (QWaylandSurface *s : surfaces)
            m_compositor->destroyClientForSurface(s);
        // Outputs and surface items refer to the windows: tear the
        // compositor down while the windows still exist.
        delete m_compositor;
        m_compositor = nullptr;
    }
    qDeleteAll(m_windows);
    m_windows.clear();
}

bool Backend56::start(const BackendConfig &config)
{
    setConfig(config);
    m_socketName = config.socketName;

    // Qt Quick 5.6 can only draw with OpenGL and aborts when it cannot (see
    // core/graphics.h): give a clear error instead, before any window exists.
    const QString noGL = openGLUnavailableReason();
    if (!noGL.isEmpty()) {
        reportFatalError(noGL);
        return false;
    }

    // The main window exists first: the 5.6 compositor adds every new
    // surface to the primary output, so an output must exist before the
    // client connects (qt-runner creates its QQuickView first for the same
    // reason).
    OuterWindow56 *main = new OuterWindow56(this, WindowMapper::MainWindowId, WindowRole::Main);
    watchSceneGraph(main);
    if (QScreen *screen = QGuiApplication::primaryScreen())
        main->resize(screen->size());
    m_windows.insert(WindowMapper::MainWindowId, main);
    registerOuterWindow(WindowMapper::MainWindowId, WindowRole::Main, main);

    m_compositor = new Compositor56(this, config.socketName.toUtf8());
    QWaylandOutput *output = m_compositor->addOutput(main);
    main->setOutput(output);
    m_compositor->setPrimaryOutput(output);
    output->setGeometry(QRect(QPoint(0, 0), main->size()));
    connect(main, &QQuickWindow::afterRendering, this, [this]() {
        sendFrameCallbacks(WindowMapper::MainWindowId);
    }, Qt::QueuedConnection);

    showOuterWindow(WindowMapper::MainWindowId);
    // With the non-threaded render loop the first frame (and so a failed
    // OpenGL context) happens inside show().
    return errorString().isEmpty();
}

void Backend56::watchSceneGraph(OuterWindow56 *window)
{
    // A connected sceneGraphError stops Qt Quick's qFatal(); 5.6's render
    // loops then skip the frame and return.
    const int windowId = window->windowId();
    const WindowRole role = window->role();
    connect(window, &QQuickWindow::sceneGraphError, this,
            [this, windowId, role](QQuickWindow::SceneGraphError, const QString &message) {
        reportFatalError(sceneGraphFailureMessage(windowId, role, message));
    });
}

QWaylandSurfaceItem *Backend56::itemFor(QWaylandSurface *surface) const
{
    if (!surface || surface->views().isEmpty())
        return nullptr;
    // QWaylandQuickCompositor::createView() always creates QWaylandSurfaceItems
    // (qt-runner relies on the same cast).
    return static_cast<QWaylandSurfaceItem *>(surface->views().first());
}

QWaylandSurface *Backend56::surfaceForKey(SurfaceKey key) const
{
    return key ? m_surfaces.value(key).data() : nullptr;
}

void Backend56::onSurfaceCreated(QWaylandSurface *surface)
{
    const SurfaceKey key = reinterpret_cast<SurfaceKey>(surface);
    m_surfaces.insert(key, surface);
    m_mapped.insert(key, false);

    connect(surface, &QWaylandSurface::mapped, this, [this, surface]() {
        surfaceStateChanged(surface);
    });
    connect(surface, &QWaylandSurface::unmapped, this, [this, key]() {
        if (m_mapped.value(key)) {
            m_mapped[key] = false;
            mapper()->unmapSurface(key);
        }
    });
    connect(surface, &QWaylandSurface::titleChanged, this, [this, surface]() {
        surfaceStateChanged(surface);
    });
    connect(surface, &QWaylandSurface::classNameChanged, this, [this, surface]() {
        surfaceStateChanged(surface);
    });
    connect(surface, &QWaylandSurface::windowTypeChanged, this, [this, surface]() {
        surfaceStateChanged(surface);
    });
    connect(surface, &QWaylandSurface::sizeChanged, this, [this, key]() {
        const int w = mapper()->windowForSurface(key);
        if (OuterWindow56 *window = m_windows.value(w))
            window->layoutItems();
    });
    connect(surface, &QWaylandSurface::surfaceDestroyed, this, [this, key]() {
        if (m_mapped.value(key))
            mapper()->unmapSurface(key);
        m_mapped.remove(key);
        m_surfaces.remove(key);
    });
}

bool Backend56::isPlaceable(QWaylandSurface *surface) const
{
    if (!surface || !surface->isMapped())
        return false;
    QtWayland::Surface *handle = surface->handle();
    if (handle && handle->isCursorSurface())
        return false;
    // A surface without a shell or subsurface role has no view.
    return !surface->views().isEmpty();
}

SurfaceInfo Backend56::infoFor(QWaylandSurface *surface) const
{
    SurfaceInfo info;
    info.title = surface->title();
    info.appId = surface->className();
    QtWayland::Surface *handle = surface->handle();
    if (handle && handle->subSurface()) {
        info.kind = SurfaceKind::SubSurface;
        // QtCompositor parents the subsurface item to its parent's item.
        QWaylandSurfaceItem *item = itemFor(surface);
        QWaylandSurfaceItem *parentItem = item ? qobject_cast<QWaylandSurfaceItem *>(item->parentItem())
                                               : nullptr;
        if (parentItem && parentItem->surface())
            info.parent = reinterpret_cast<SurfaceKey>(parentItem->surface());
        return info;
    }
    switch (surface->windowType()) {
    case QWaylandSurface::Transient:
        info.kind = SurfaceKind::Transient;
        break;
    case QWaylandSurface::Popup:
        info.kind = SurfaceKind::Popup;
        break;
    default:
        info.kind = SurfaceKind::Toplevel;
        break;
    }
    if (info.kind != SurfaceKind::Toplevel && surface->transientParent())
        info.parent = reinterpret_cast<SurfaceKey>(surface->transientParent());
    return info;
}

void Backend56::surfaceStateChanged(QWaylandSurface *surface)
{
    const SurfaceKey key = reinterpret_cast<SurfaceKey>(surface);
    const bool placeable = isPlaceable(surface);
    if (placeable && !m_mapped.value(key)) {
        m_mapped[key] = true;
        const SurfaceInfo info = infoFor(surface);
        const int w = mapper()->mapSurface(key, info);
        logDecision(QStringLiteral("map surface title='%1' class='%2' -> window %3 (%4)")
                    .arg(info.title, info.appId).arg(w)
                    .arg(w ? windowRoleName(mapper()->roleOf(w)) : QStringLiteral("parked")));
    } else if (placeable) {
        mapper()->updateSurface(key, infoFor(surface));
    }
}

OuterWindow56 *Backend56::createOuterWindow(int windowId, WindowRole role)
{
    OuterWindow56 *window = new OuterWindow56(this, windowId, role);
    watchSceneGraph(window);
    if (role == WindowRole::Cover)
        window->resize(1, 1);   // follows the cover surface size
    else if (QScreen *screen = QGuiApplication::primaryScreen())
        window->resize(screen->size());
    QWaylandOutput *output = m_compositor->addOutput(window);
    window->setOutput(output);
    output->setGeometry(QRect(QPoint(0, 0), window->size()));
    connect(window, &QQuickWindow::afterRendering, this, [this, windowId]() {
        sendFrameCallbacks(windowId);
    }, Qt::QueuedConnection);
    m_windows.insert(windowId, window);
    registerOuterWindow(windowId, role, window);
    return window;
}

void Backend56::onWindowCreated(int windowId, WindowRole role)
{
    createOuterWindow(windowId, role);
}

void Backend56::onWindowDestroyed(int windowId)
{
    OuterWindow56 *window = m_windows.take(windowId);
    unregisterOuterWindow(windowId);
    if (window) {
        window->hide();
        window->deleteLater();
    }
}

void Backend56::moveToOutput(QWaylandSurface *surface, QWaylandOutput *output)
{
    QtWayland::Surface *handle = surface->handle();
    if (!handle || !output)
        return;
    const QList<QtWayland::Output *> current = handle->outputs();
    for (QtWayland::Output *o : current) {
        if (o != output->handle())
            handle->removeFromOutput(o);
    }
    handle->addToOutput(output->handle());
    surface->setMainOutput(output);
}

void Backend56::onSurfaceAssigned(SurfaceKey key, int windowId)
{
    QWaylandSurface *surface = surfaceForKey(key);
    OuterWindow56 *window = m_windows.value(windowId);
    if (!surface || !window)
        return;
    moveToOutput(surface, window->output());
    window->layoutItems();
    if (mapper()->primarySurface(windowId) == key) {
        if (!window->isVisible())
            showOuterWindow(windowId);
        if (QWaylandSurfaceItem *item = itemFor(surface)) {
            if (window->isActive() || windowId == WindowMapper::MainWindowId)
                item->takeFocus();
        }
    }
    window->update();
}

void Backend56::onSurfaceRemoved(SurfaceKey key, int windowId)
{
    QWaylandSurface *surface = surfaceForKey(key);
    OuterWindow56 *window = m_windows.value(windowId);
    QWaylandSurfaceItem *item = itemFor(surface);
    if (item && window && item->window() == window && item->parentItem() == window->contentItem())
        item->setParentItem(nullptr);
    if (window)
        window->update();
}

void Backend56::sendFrameCallbacks(int windowId)
{
    if (!m_compositor)
        return;
    QList<QWaylandSurface *> visible;
    for (SurfaceKey key : mapper()->surfacesInWindow(windowId)) {
        if (QWaylandSurface *s = surfaceForKey(key))
            visible << s;
    }
    if (windowId == WindowMapper::MainWindowId) {
        // Surfaces that are not placed yet (no role or no buffer) still need
        // their frame callbacks, as in qt-runner's sendCallbacks().
        for (auto it = m_surfaces.constBegin(); it != m_surfaces.constEnd(); ++it) {
            if (it.value() && !mapper()->isMapped(it.key()))
                visible << it.value().data();
        }
    }
    if (!visible.isEmpty())
        m_compositor->sendFrameCallbacks(visible);
}

void Backend56::outerWindowActivated(int windowId)
{
    QWaylandSurface *surface = surfaceForKey(mapper()->primarySurface(windowId));
    if (QWaylandSurfaceItem *item = itemFor(surface))
        item->takeFocus();
}

void Backend56::onKeyboardRectChanged()
{
    if (!config().followKeyboard)
        return;
    m_keyboardHeight = state()->keyboardHeight();
    if (OuterWindow56 *main = m_windows.value(WindowMapper::MainWindowId))
        main->layoutItems();
}

} // namespace keel
