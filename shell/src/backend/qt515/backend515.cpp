/****************************************************************************
**
** SPDX-FileCopyrightText: 2017 The Qt Company Ltd.
** SPDX-FileCopyrightText: 2023 Artur Gaspar
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from newcompositor src/compositor.cpp, src/view.cpp and
** src/window.cpp (BSD-3-Clause). Full licence text in backend515.h and
** upstream-licenses/. See PROVENANCE.md.
**
****************************************************************************/

#include "backend515.h"

#include <QDebug>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QScreen>
#include <QSet>
#include <QTouchEvent>
#include <QWaylandBufferRef>
#include <QWaylandClient>
#include <QWaylandOutput>
#include <QWaylandOutputMode>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandWlShell>
#include <QWaylandWlShellSurface>
#include <QWaylandXdgShell>
#include <QWaylandXdgDecorationManagerV1>

#include "../../core/shellstate.h"

namespace keel {

View515::View515(QWaylandSurface *surface, QObject *parent)
{
    setParent(parent);
    setSurface(surface);
}

bool View515::hasRole() const
{
    return wlShellSurface || xdgToplevel || xdgPopup || kind == SurfaceKind::SubSurface;
}

SurfaceInfo View515::info() const
{
    SurfaceInfo i;
    if (xdgToplevel) {
        i.title = xdgToplevel->title();
        i.appId = xdgToplevel->appId();
    } else if (wlShellSurface) {
        i.title = wlShellSurface->title();
        i.appId = wlShellSurface->className();
    }
    i.kind = kind == SurfaceKind::Unknown ? SurfaceKind::Toplevel : kind;
    i.parent = parentView ? parentView->key() : 0;
    return i;
}

QPointF View515::position() const
{
    if (parentView && kind != SurfaceKind::Toplevel && kind != SurfaceKind::Unknown)
        return parentView->position() + relativePosition;
    return QPointF();
}

void View515::sendConfigure(const QSize &size) const
{
    if (size.isEmpty())
        return;
    if (xdgToplevel)
        xdgToplevel->sendMaximized(size);
    else if (wlShellSurface)
        wlShellSurface->sendConfigure(size, QWaylandWlShellSurface::NoneEdge);
}

void View515::sendClose() const
{
    if (xdgToplevel)
        xdgToplevel->sendClose();
    else if (xdgPopup)
        xdgPopup->sendPopupDone();
}

OuterWindow515::OuterWindow515(Backend515 *backend, int windowId)
    : m_backend(backend)
    , m_windowId(windowId)
{
}

void OuterWindow515::addView(View515 *view)
{
    if (!m_views.contains(view))
        m_views.append(view);
    update();
}

void OuterWindow515::removeView(View515 *view)
{
    m_views.removeAll(view);
    if (m_mouseView == view)
        m_mouseView = nullptr;
    update();
}

QList<View515 *> OuterWindow515::views() const
{
    QList<View515 *> result;
    for (const QPointer<View515> &v : m_views) {
        if (v)
            result.append(v.data());
    }
    return result;
}

View515 *OuterWindow515::primaryView() const
{
    const SurfaceKey key = m_backend->mapper()->primarySurface(m_windowId);
    for (View515 *v : views()) {
        if (v->key() == key)
            return v;
    }
    return nullptr;
}

void OuterWindow515::updateOutputMode()
{
    if (!m_output || size().isEmpty())
        return;
    QSize outputSize = size();
    if (m_backend->mapper()->roleOf(m_windowId) == WindowRole::Main)
        outputSize.setHeight(qMax(1, outputSize.height() - m_backend->keyboardHeight()));
    const int refresh = screen() ? static_cast<int>(screen()->refreshRate() * 1000) : 60000;
    QWaylandOutputMode mode(outputSize, refresh);
    if (!m_output->modes().contains(mode))
        m_output->addMode(mode, false);
    m_output->setCurrentMode(mode);
}

void OuterWindow515::resizeEvent(QResizeEvent *event)
{
    QRasterWindow::resizeEvent(event);
    updateOutputMode();
    if (m_backend->mapper()->roleOf(m_windowId) != WindowRole::Cover) {
        if (View515 *v = primaryView())
            v->sendConfigure(m_output ? m_output->geometry().size() : size());
    }
}

void OuterWindow515::paintEvent(QPaintEvent *)
{
    if (m_output)
        m_output->frameStarted();

    QPainter p(this);
    p.setCompositionMode(QPainter::CompositionMode_Source);
    p.fillRect(QRect(QPoint(), size()), Qt::transparent);
    p.setCompositionMode(QPainter::CompositionMode_SourceOver);

    for (View515 *view : views()) {
        view->advance();
        QWaylandBufferRef buffer = view->currentBuffer();
        if (!buffer.hasContent())
            continue;
        if (buffer.isSharedMemory()) {
            const QImage image = buffer.image();
            const QSize dest = view->surface() ? view->surface()->destinationSize() : image.size();
            p.drawImage(QRectF(view->position(), QSizeF(dest)), image);
        }
        // Non-shm (EGL) buffers need the GL renderer; the Sailfish backend
        // (qt56) handles them through QtQuick. See README "Backends".
    }
    p.end();

    if (m_output)
        m_output->sendFrameCallbacks();
}

View515 *OuterWindow515::viewAt(const QPointF &point) const
{
    const QList<View515 *> list = views();
    for (auto it = list.crbegin(); it != list.crend(); ++it) {
        View515 *view = *it;
        QWaylandSurface *surface = view->surface();
        if (surface && surface->hasContent()) {
            const QRectF geom(view->position(), surface->destinationSize());
            if (geom.contains(point))
                return view;
        }
    }
    return nullptr;
}

void OuterWindow515::mousePressEvent(QMouseEvent *e)
{
    if (!m_mouseView) {
        m_mouseView = viewAt(e->localPos());
        if (!m_mouseView)
            return;
        QMouseEvent moveEvent(QEvent::MouseMove, e->localPos(), e->globalPos(),
                              Qt::NoButton, Qt::NoButton, e->modifiers());
        mouseMoveEvent(&moveEvent);
    }
    QWaylandSeat *seat = m_backend->compositor()->seatFor(e);
    seat->sendMousePressEvent(e->button());
    m_backend->setFocusSurface(m_mouseView->surface());
}

void OuterWindow515::mouseReleaseEvent(QMouseEvent *e)
{
    m_backend->compositor()->seatFor(e)->sendMouseReleaseEvent(e->button());
    if (e->buttons() == Qt::NoButton)
        m_mouseView = nullptr;
}

void OuterWindow515::mouseMoveEvent(QMouseEvent *e)
{
    View515 *view = m_mouseView ? m_mouseView.data() : viewAt(e->localPos());
    if (!view)
        return;
    m_backend->compositor()->seatFor(e)->sendMouseMoveEvent(view, e->localPos() - view->position(),
                                                            e->globalPos());
}

void OuterWindow515::keyPressEvent(QKeyEvent *e)
{
    m_backend->compositor()->seatFor(e)->sendFullKeyEvent(e);
}

void OuterWindow515::keyReleaseEvent(QKeyEvent *e)
{
    m_backend->compositor()->seatFor(e)->sendFullKeyEvent(e);
}

void OuterWindow515::touchEvent(QTouchEvent *e)
{
    QWaylandSeat *seat = m_backend->compositor()->seatFor(e);
    QSet<QWaylandClient *> clients;
    bool unhandled = false;
    for (const QTouchEvent::TouchPoint &tp : e->touchPoints()) {
        View515 *view = viewAt(tp.pos());
        if (!view)
            continue;
        const uint serial = seat->sendTouchPointEvent(view->surface(), tp.id(),
                                                      tp.pos() - view->position(), tp.state());
        if (serial == 0 && (tp.state() == Qt::TouchPointPressed
                            || tp.state() == Qt::TouchPointReleased))
            unhandled = true;
        else if (tp.state() == Qt::TouchPointReleased)
            m_backend->setFocusSurface(view->surface());
        clients.insert(view->surface()->client());
    }
    for (QWaylandClient *client : clients)
        seat->sendTouchFrameEvent(client);
    if (unhandled)
        e->ignore();   // let Qt synthesise mouse events
}

Backend515::Backend515(ShellState *state, QObject *parent)
    : Backend(state, parent)
{
    connect(mapper(), &WindowMapper::windowCreated, this, &Backend515::onWindowCreated);
    connect(mapper(), &WindowMapper::windowDestroyed, this, &Backend515::onWindowDestroyed);
    connect(mapper(), &WindowMapper::surfaceAssigned, this, &Backend515::onSurfaceAssigned);
    connect(mapper(), &WindowMapper::surfaceRemoved, this, &Backend515::onSurfaceRemoved);
    connect(state, &ShellState::keyboardRectChanged, this, &Backend515::onKeyboardRectChanged);
}

Backend515::~Backend515()
{
    qDeleteAll(m_windows);
    m_windows.clear();
}

QString Backend515::socketName() const
{
    return QString::fromUtf8(const_cast<QWaylandCompositor &>(m_compositor).socketName());
}

bool Backend515::start(const BackendConfig &config)
{
    setConfig(config);

    connect(&m_compositor, &QWaylandCompositor::surfaceCreated,
            this, &Backend515::onSurfaceCreated);
    connect(&m_compositor, &QWaylandCompositor::subsurfaceChanged,
            this, &Backend515::onSubsurfaceChanged);

    m_wlShell = new QWaylandWlShell(&m_compositor);
    connect(m_wlShell, &QWaylandWlShell::wlShellSurfaceCreated,
            this, &Backend515::onWlShellSurfaceCreated);
    m_xdgShell = new QWaylandXdgShell(&m_compositor);
    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated,
            this, &Backend515::onXdgToplevelCreated);
    connect(m_xdgShell, &QWaylandXdgShell::popupCreated,
            this, &Backend515::onXdgPopupCreated);
    // Ask xdg clients not to draw decorations (newcompositor does the same).
    auto *decorations = new QWaylandXdgDecorationManagerV1;
    decorations->setExtensionContainer(&m_compositor);
    decorations->setParent(&m_compositor);
    decorations->setPreferredMode(QWaylandXdgToplevel::ServerSideDecoration);

    m_compositor.setSocketName(config.socketName.toUtf8());

    // The main window exists from the start (like qt-runner), so the app
    // shows up in Lipstick immediately and its output is known before the
    // client creates surfaces.
    createOuterWindow(WindowMapper::MainWindowId, WindowRole::Main);

    m_compositor.create();
    decorations->initialize();
    if (!m_compositor.isCreated())
        return false;

    showOuterWindow(WindowMapper::MainWindowId);
    return true;
}

OuterWindow515 *Backend515::createOuterWindow(int windowId, WindowRole role)
{
    auto *window = new OuterWindow515(this, windowId);
    if (role == WindowRole::Cover) {
        window->resize(1, 1);   // resized to the cover surface once it has content
    } else if (QScreen *screen = QGuiApplication::primaryScreen()) {
        window->resize(screen->size());
    }
    auto *output = new QWaylandOutput(&m_compositor, window);
    output->setParent(window);
    if (QScreen *screen = window->screen()) {
        output->setManufacturer(screen->manufacturer());
        output->setModel(screen->model());
        output->setPhysicalSize(screen->physicalSize().toSize());
    }
    window->setOutput(output);
    const int refresh = window->screen() ? static_cast<int>(window->screen()->refreshRate() * 1000) : 60000;
    QWaylandOutputMode mode(window->size(), refresh);
    output->addMode(mode, true);
    output->setCurrentMode(mode);
    if (!m_compositor.defaultOutput() || role == WindowRole::Main)
        m_compositor.setDefaultOutput(output);

    m_windows.insert(windowId, window);
    registerOuterWindow(windowId, role, window);
    return window;
}

View515 *Backend515::viewFor(QWaylandSurface *surface) const
{
    return surface ? m_views.value(reinterpret_cast<SurfaceKey>(surface)).data() : nullptr;
}

View515 *Backend515::viewForKey(SurfaceKey key) const
{
    return m_views.value(key).data();
}

void Backend515::onSurfaceCreated(QWaylandSurface *surface)
{
    auto *view = new View515(surface, this);
    const SurfaceKey key = view->key();
    m_views.insert(key, view);

    connect(surface, &QWaylandSurface::hasContentChanged, this, [this, view]() {
        surfaceStateChanged(view);
    });
    connect(surface, &QWaylandSurface::redraw, this, [this, key]() {
        const int w = mapper()->windowForSurface(key);
        if (OuterWindow515 *win = m_windows.value(w))
            win->update();
    });
    connect(surface, &QWaylandSurface::destinationSizeChanged, this, [this, key]() {
        const int w = mapper()->windowForSurface(key);
        OuterWindow515 *win = m_windows.value(w);
        if (win && mapper()->roleOf(w) == WindowRole::Cover
                && mapper()->primarySurface(w) == key) {
            View515 *v = viewForKey(key);
            if (v && v->surface() && !v->surface()->destinationSize().isEmpty())
                win->resize(v->surface()->destinationSize());
        }
    });
    connect(surface, &QWaylandSurface::subsurfacePositionChanged, this,
            [this, view](const QPoint &pos) {
        view->relativePosition = pos;
        const int w = mapper()->windowForSurface(view->key());
        if (OuterWindow515 *win = m_windows.value(w))
            win->update();
    });
    connect(surface, &QWaylandSurface::surfaceDestroyed, this, [this, view, key]() {
        mapper()->unmapSurface(key);
        m_views.remove(key);
        view->deleteLater();
    });
}

void Backend515::surfaceStateChanged(View515 *view)
{
    QWaylandSurface *surface = view->surface();
    if (!surface)
        return;
    const bool shouldMap = surface->hasContent() && !surface->isCursorSurface() && view->hasRole();
    if (shouldMap && !view->mapped) {
        view->mapped = true;
        const SurfaceInfo info = view->info();
        const int w = mapper()->mapSurface(view->key(), info);
        logDecision(QStringLiteral("map surface title='%1' app_id='%2' -> window %3 (%4)")
                    .arg(info.title, info.appId).arg(w)
                    .arg(w ? windowRoleName(mapper()->roleOf(w)) : QStringLiteral("parked")));
    } else if (!shouldMap && view->mapped) {
        view->mapped = false;
        mapper()->unmapSurface(view->key());
    } else if (view->mapped) {
        mapper()->updateSurface(view->key(), view->info());
    }
}

void Backend515::onSubsurfaceChanged(QWaylandSurface *child, QWaylandSurface *parent)
{
    View515 *view = viewFor(child);
    if (!view)
        return;
    view->kind = SurfaceKind::SubSurface;
    view->parentView = viewFor(parent);
    surfaceStateChanged(view);
}

void Backend515::onWlShellSurfaceCreated(QWaylandWlShellSurface *shellSurface)
{
    View515 *view = viewFor(shellSurface->surface());
    if (!view)
        return;
    view->wlShellSurface = shellSurface;
    view->kind = SurfaceKind::Toplevel;
    auto refresh = [this, view]() { surfaceStateChanged(view); };
    connect(shellSurface, &QWaylandWlShellSurface::titleChanged, this, refresh);
    connect(shellSurface, &QWaylandWlShellSurface::classNameChanged, this, refresh);
    connect(shellSurface, &QWaylandWlShellSurface::setDefaultToplevel, this, [this, view]() {
        view->kind = SurfaceKind::Toplevel;
        view->parentView = nullptr;
        surfaceStateChanged(view);
    });
    connect(shellSurface, &QWaylandWlShellSurface::setTransient, this,
            [this, view](QWaylandSurface *parent, const QPoint &rel, bool) {
        view->kind = SurfaceKind::Transient;
        view->parentView = viewFor(parent);
        view->relativePosition = rel;
        surfaceStateChanged(view);
    });
    connect(shellSurface, &QWaylandWlShellSurface::setPopup, this,
            [this, view](QWaylandSeat *, QWaylandSurface *parent, const QPoint &rel) {
        view->kind = SurfaceKind::Popup;
        view->parentView = viewFor(parent);
        view->relativePosition = rel;
        surfaceStateChanged(view);
    });
    surfaceStateChanged(view);
}

void Backend515::onXdgToplevelCreated(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface)
{
    View515 *view = viewFor(xdgSurface->surface());
    if (!view)
        return;
    view->xdgToplevel = toplevel;
    view->kind = SurfaceKind::Toplevel;
    auto refresh = [this, view]() {
        QWaylandXdgToplevel *parent = view->xdgToplevel ? view->xdgToplevel->parentToplevel()
                                                        : nullptr;
        if (parent && parent->xdgSurface()) {
            view->kind = SurfaceKind::Transient;
            view->parentView = viewFor(parent->xdgSurface()->surface());
        } else {
            view->kind = SurfaceKind::Toplevel;
            view->parentView = nullptr;
        }
        surfaceStateChanged(view);
    };
    connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, refresh);
    connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, refresh);
    connect(toplevel, &QWaylandXdgToplevel::parentToplevelChanged, this, refresh);
    refresh();
}

void Backend515::onXdgPopupCreated(QWaylandXdgPopup *popup, QWaylandXdgSurface *xdgSurface)
{
    View515 *view = viewFor(xdgSurface->surface());
    if (!view)
        return;
    view->xdgPopup = popup;
    view->kind = SurfaceKind::Popup;
    view->parentView = popup->parentXdgSurface()
            ? viewFor(popup->parentXdgSurface()->surface()) : nullptr;
    view->relativePosition = popup->anchorRect().topLeft() + popup->offset();
    surfaceStateChanged(view);
}

void Backend515::onWindowCreated(int windowId, WindowRole role)
{
    createOuterWindow(windowId, role);
}

void Backend515::onWindowDestroyed(int windowId)
{
    OuterWindow515 *window = m_windows.take(windowId);
    unregisterOuterWindow(windowId);
    if (window) {
        window->hide();
        window->deleteLater();
    }
}

void Backend515::configurePrimary(int windowId)
{
    OuterWindow515 *window = m_windows.value(windowId);
    View515 *view = viewForKey(mapper()->primarySurface(windowId));
    if (!window || !view)
        return;
    if (mapper()->roleOf(windowId) == WindowRole::Cover) {
        if (view->surface() && !view->surface()->destinationSize().isEmpty())
            window->resize(view->surface()->destinationSize());
    } else {
        view->sendConfigure(window->output() ? window->output()->geometry().size()
                                             : window->size());
    }
}

void Backend515::onSurfaceAssigned(SurfaceKey key, int windowId)
{
    View515 *view = viewForKey(key);
    OuterWindow515 *window = m_windows.value(windowId);
    if (!view || !window)
        return;
    view->setOutput(window->output());
    window->addView(view);
    if (mapper()->primarySurface(windowId) == key) {
        configurePrimary(windowId);
        if (!window->isVisible())
            showOuterWindow(windowId);
        if (window->isActive() || windowId == WindowMapper::MainWindowId)
            setFocusSurface(view->surface());
    }
}

void Backend515::onSurfaceRemoved(SurfaceKey key, int windowId)
{
    View515 *view = viewForKey(key);
    OuterWindow515 *window = m_windows.value(windowId);
    if (window && view)
        window->removeView(view);
}

void Backend515::setFocusSurface(QWaylandSurface *surface)
{
    QWaylandSeat *seat = m_compositor.defaultSeat();
    if (!seat)
        return;
    if (!surface) {
        seat->setKeyboardFocus(nullptr);
        return;
    }
    View515 *view = viewFor(surface);
    if (view && view->kind == SurfaceKind::Popup)
        return;
    seat->setKeyboardFocus(surface);
}

void Backend515::outerWindowActivated(int windowId)
{
    View515 *view = viewForKey(mapper()->primarySurface(windowId));
    if (view)
        setFocusSurface(view->surface());
}

void Backend515::onKeyboardRectChanged()
{
    if (!config().followKeyboard)
        return;
    m_keyboardHeight = state()->keyboardHeight();
    if (OuterWindow515 *main = m_windows.value(WindowMapper::MainWindowId)) {
        QResizeEvent ev(main->size(), main->size());
        QCoreApplication::sendEvent(main, &ev);
    }
}

} // namespace keel
