// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-wl-shell: the Qt 6 Wayland shell integration Keel apps use with
// Lipstick (QT_WAYLAND_SHELL_INTEGRATION, set by Keel's launcher). It speaks
// the protocol path of native Qt 5 Silica apps: a wl_shell surface plus a
// qt_extended_surface (window properties, onscreen visibility, close, raise
// and lower) for every window.
//
// Qt 6's own wl-shell integration has two problems on Lipstick:
//
//  * It maps qt_extended_surface.onscreen_visibility to
//    QWindow::setVisibility(). Lipstick sends Hidden when a window leaves the
//    screen (display off, the app in the switcher, the cover off screen) and
//    FullScreen or Minimized when it comes back. Under Qt 5 a hidden window
//    kept its wl_surface; Qt 6's QWaylandWindow::setVisible(false) destroys
//    the surface and its role, so the window Lipstick knew is gone, and the
//    next "show" (if any arrives) maps a new window. The app keeps running
//    with no window. Here the surface stays, and the window stays exposed:
//    on the Jolla Phone Lipstick sends Hidden right after an app comes to
//    the front (Minimized, then Hidden, with the app on screen), so treating
//    Hidden as "not exposed" left every foreground Keel app throttled
//    (Pacific scrolled at 9 frames a second). A window Lipstick does not
//    show gets no frame callbacks, which throttles Qt's rendering by itself.
//    The value stays readable as the keelOnscreenVisibility property.
//  * It sends window properties with Qt 6's QDataStream format, and Qt 6.9
//    dropped qt_extended_surface altogether. Here properties are written in
//    Qt 5.6's format, which is what Lipstick decodes.
//
// The cover window (QWindow property keelCover, set by Keel.Shell) is the
// exception to "always exposed": it counts as exposed only until it has
// drawn its first frame (Lipstick learns of the cover from its first
// buffer) and while the app is not active, the only time Lipstick shows it.
// Qt 6's threaded render loop advances animations in step with the
// display only while exactly one window is exposed; with the cover exposed
// too it drives them from a plain timer, out of step with the frames, and
// every scroll and page transition of a foreground app moved unevenly.
//
// It also keeps the cover window out of full screen: Lipstick tells every client to show its
// windows full screen (qt_windowmanager), and a full-screen cover would be
// laid out at the size of the screen.
//
// Only the shell integration plugin API (QWaylandShellIntegration,
// QWaylandShellSurface, QWaylandWindow) is used; the protocols are driven
// with plain libwayland-client calls.

#include <QtWaylandClient/private/qwaylanddisplay_p.h>
#include <QtWaylandClient/private/qwaylandinputdevice_p.h>
#include <QtWaylandClient/private/qwaylandshellintegration_p.h>
#include <QtWaylandClient/private/qwaylandshellintegrationplugin_p.h>
#include <QtWaylandClient/private/qwaylandshellsurface_p.h>
#include <QtWaylandClient/private/qwaylandwindow_p.h>

#include <QtCore/QDataStream>
#include <QtCore/QMetaMethod>
#include <QtCore/QLoggingCategory>
#include <QtCore/QVariant>
#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>
#include <qpa/qwindowsysteminterface.h>

#include <wayland-client.h>

#include "surface-extension-client-protocol.h"

#include <cstring>
#include <memory>

Q_LOGGING_CATEGORY(lcKeelWlShell, "keel.wlshell")

QT_BEGIN_NAMESPACE

namespace QtWaylandClient {

class KeelShellIntegration;

namespace {


bool isCoverWindow(const QWindow *window)
{
    return window && window->property("keelCover").toBool();
}

QByteArray qt5Variant(const QVariant &value)
{
    // Lipstick (Qt 5.6) reads generic properties with QDataStream's Qt 5.6
    // format (QWaylandSurface::windowProperties).
    QByteArray bytes;
    QDataStream ds(&bytes, QIODevice::WriteOnly);
    ds.setVersion(QDataStream::Qt_5_6);
    ds << value;
    return bytes;
}

} // namespace

// Exposure of the cover window (see the top of this file).
class KeelCoverExposure : public QObject
{
    Q_OBJECT

public:
    explicit KeelCoverExposure(QWaylandWindow *window)
        : m_window(window)
    {
        connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, &KeelCoverExposure::update);
        // QQuickWindow::frameSwapped(), by name: this plugin does not link
        // Qt Quick. Emitted on the render thread; queued to this object.
        QWindow *w = window->window();
        const int signal = w->metaObject()->indexOfSignal("frameSwapped()");
        if (signal >= 0) {
            m_frameSwapped = connect(w, w->metaObject()->method(signal), this,
                                     staticMetaObject.method(staticMetaObject.indexOfSlot("drawn()")));
        } else {
            m_drawn = true;
        }
    }

    bool exposed() const { return m_exposed; }

public Q_SLOTS:
    void drawn()
    {
        if (m_drawn)
            return;
        m_drawn = true;
        disconnect(m_frameSwapped);
        update();
    }

private:
    void update()
    {
        const bool exposed = !m_drawn || QGuiApplication::applicationState() != Qt::ApplicationActive;
        if (exposed == m_exposed)
            return;
        m_exposed = exposed;
        qCDebug(lcKeelWlShell) << m_window->window() << "cover exposed" << exposed;
        // An expose with the window's size makes Qt draw a fresh cover for
        // Lipstick to show; an empty one stops its rendering.
        QWindowSystemInterface::handleExposeEvent(
                m_window->window(), exposed ? QRegion(QRect(QPoint(), m_window->geometry().size())) : QRegion());
    }

    QWaylandWindow *m_window;
    QMetaObject::Connection m_frameSwapped;
    bool m_drawn = false;
    bool m_exposed = true;
};

class KeelShellSurface : public QWaylandShellSurface
{
public:
    KeelShellSurface(KeelShellIntegration *shell, QWaylandWindow *window);
    ~KeelShellSurface() override;

    void setTitle(const QString &title) override
    {
        wl_shell_surface_set_title(m_shellSurface, title.toUtf8().constData());
    }
    void setAppId(const QString &appId) override
    {
        wl_shell_surface_set_class(m_shellSurface, appId.toUtf8().constData());
    }

    void raise() override
    {
        if (m_extended)
            qt_extended_surface_raise(m_extended);
    }
    void lower() override
    {
        if (m_extended)
            qt_extended_surface_lower(m_extended);
    }

    void setContentOrientationMask(Qt::ScreenOrientations orientation) override
    {
        if (!m_extended)
            return;
        // Qt::ScreenOrientation and the protocol's orientation enum have the
        // same values.
        qt_extended_surface_set_content_orientation_mask(m_extended, static_cast<int>(orientation.toInt()));
    }

    void setWindowFlags(Qt::WindowFlags flags) override
    {
        if (!m_extended)
            return;
        int wl = 0;
        if (flags & Qt::WindowStaysOnTopHint)
            wl |= QT_EXTENDED_SURFACE_WINDOWFLAG_STAYSONTOP;
        if (flags & Qt::WindowOverridesSystemGestures)
            wl |= QT_EXTENDED_SURFACE_WINDOWFLAG_OVERRIDESSYSTEMGESTURES;
        if (flags & Qt::BypassWindowManagerHint)
            wl |= QT_EXTENDED_SURFACE_WINDOWFLAG_BYPASSWINDOWMANAGER;
        qt_extended_surface_set_window_flags(m_extended, wl);
    }

    void sendProperty(const QString &name, const QVariant &value) override
    {
        if (!m_extended)
            return;
        const QByteArray bytes = qt5Variant(value);
        wl_array array {};
        wl_array_init(&array);
        if (void *data = wl_array_add(&array, static_cast<size_t>(bytes.size())))
            std::memcpy(data, bytes.constData(), static_cast<size_t>(bytes.size()));
        qt_extended_surface_update_generic_property(m_extended, name.toUtf8().constData(), &array);
        wl_array_release(&array);
    }

    // Always exposed, except the cover: Lipstick's onscreen_visibility is
    // not a reliable "on screen" signal (setOnscreenVisibility()).
    bool isExposed() const override { return m_cover ? m_cover->exposed() : true; }

    void applyConfigure() override
    {
        if (m_pendingStates != m_appliedStates)
            m_window->handleWindowStatesChanged(m_pendingStates);
        if (!m_pendingSize.isEmpty())
            resizeFromApplyConfigure(m_pendingSize);
        m_appliedStates = m_pendingStates;
    }

    void requestWindowStates(Qt::WindowStates states) override
    {
        // The cover stays a plain top-level window at the size the app gives
        // it; Lipstick scales its buffer into the switcher.
        if (isCoverWindow(m_window->window()))
            states &= ~(Qt::WindowFullScreen | Qt::WindowMaximized);
        const Qt::WindowStates changed = m_pendingStates ^ states;
        const Qt::WindowStates added = changed & states;
        if (added & Qt::WindowFullScreen) {
            wl_shell_surface_set_fullscreen(m_shellSurface, WL_SHELL_SURFACE_FULLSCREEN_METHOD_DEFAULT, 0,
                                            nullptr);
        } else if (added & Qt::WindowMaximized) {
            wl_shell_surface_set_maximized(m_shellSurface, nullptr);
        } else if ((changed & (Qt::WindowFullScreen | Qt::WindowMaximized))
                   && !(states & (Qt::WindowFullScreen | Qt::WindowMaximized))) {
            setRole();
            m_pendingSize = QSize();
        }
        m_pendingStates = states & ~Qt::WindowMinimized;
        applyConfigureWhenPossible();
    }

    bool wantsDecorations() const override { return false; }

    wl_shell_surface *shellSurface() const { return m_shellSurface; }

    // wl_shell_surface events
    static void handlePing(void *data, wl_shell_surface *surface, uint32_t serial)
    {
        Q_UNUSED(data)
        wl_shell_surface_pong(surface, serial);
    }
    static void handleConfigure(void *data, wl_shell_surface *, uint32_t, int32_t width, int32_t height)
    {
        auto *self = static_cast<KeelShellSurface *>(data);
        if (width > 0 && height > 0)
            self->m_pendingSize = QSize(width, height);
        self->applyConfigureWhenPossible();
    }
    static void handlePopupDone(void *data, wl_shell_surface *)
    {
        auto *self = static_cast<KeelShellSurface *>(data);
        QWindowSystemInterface::handleCloseEvent(self->m_window->window());
    }

    // qt_extended_surface events
    static void handleOnscreenVisibility(void *data, qt_extended_surface *, int32_t visibility)
    {
        static_cast<KeelShellSurface *>(data)->setOnscreenVisibility(visibility);
    }
    static void handleSetGenericProperty(void *data, qt_extended_surface *, const char *name, wl_array *value)
    {
        auto *self = static_cast<KeelShellSurface *>(data);
        QByteArray bytes(static_cast<const char *>(value->data), static_cast<qsizetype>(value->size));
        QDataStream ds(bytes);
        ds.setVersion(QDataStream::Qt_5_6);
        QVariant v;
        ds >> v;
        self->m_window->setProperty(QString::fromUtf8(name), v);
    }
    static void handleClose(void *data, qt_extended_surface *)
    {
        auto *self = static_cast<KeelShellSurface *>(data);
        QWindowSystemInterface::handleCloseEvent(self->m_window->window());
    }

private:
    void setRole();
    void setOnscreenVisibility(int visibility);

    QWaylandWindow *m_window;
    wl_shell_surface *m_shellSurface = nullptr;
    qt_extended_surface *m_extended = nullptr;
    QSize m_pendingSize;
    Qt::WindowStates m_pendingStates = Qt::WindowNoState;
    Qt::WindowStates m_appliedStates = Qt::WindowNoState;
    std::unique_ptr<KeelCoverExposure> m_cover;
};

namespace {
const wl_shell_surface_listener kShellSurfaceListener = {
    KeelShellSurface::handlePing,
    KeelShellSurface::handleConfigure,
    KeelShellSurface::handlePopupDone,
};
const qt_extended_surface_listener kExtendedSurfaceListener = {
    KeelShellSurface::handleOnscreenVisibility,
    KeelShellSurface::handleSetGenericProperty,
    KeelShellSurface::handleClose,
};
} // namespace

class KeelShellIntegration : public QWaylandShellIntegration
{
public:
    KeelShellIntegration() = default;
    ~KeelShellIntegration() override
    {
        if (m_extension)
            qt_surface_extension_destroy(m_extension);
        if (m_shell)
            wl_shell_destroy(m_shell);
    }

    bool initialize(QWaylandDisplay *display) override
    {
        m_display = display;
        for (const QWaylandDisplay::RegistryGlobal &global : display->globals()) {
            if (global.interface == QLatin1String("wl_shell") && !m_shell) {
                m_shell = static_cast<wl_shell *>(
                        wl_registry_bind(global.registry, global.id, &wl_shell_interface, 1));
            } else if (global.interface == QLatin1String("qt_surface_extension") && !m_extension) {
                m_extension = static_cast<qt_surface_extension *>(
                        wl_registry_bind(global.registry, global.id, &qt_surface_extension_interface, 1));
            }
        }
        if (!m_shell)
            qCWarning(lcKeelWlShell) << "the compositor has no wl_shell";
        return m_shell != nullptr;
    }

    QWaylandShellSurface *createShellSurface(QWaylandWindow *window) override
    {
        return new KeelShellSurface(this, window);
    }

    void *nativeResourceForWindow(const QByteArray &resource, QWindow *window) override
    {
        if (resource.toLower() == "wl_shell_surface") {
            if (auto *w = static_cast<QWaylandWindow *>(window->handle())) {
                if (auto *s = dynamic_cast<KeelShellSurface *>(w->shellSurface()))
                    return s->shellSurface();
            }
        }
        return nullptr;
    }

    wl_shell *shell() const { return m_shell; }
    qt_surface_extension *extension() const { return m_extension; }
    QWaylandDisplay *display() const { return m_display; }

private:
    QWaylandDisplay *m_display = nullptr;
    wl_shell *m_shell = nullptr;
    qt_surface_extension *m_extension = nullptr;
};

KeelShellSurface::KeelShellSurface(KeelShellIntegration *shell, QWaylandWindow *window)
    : QWaylandShellSurface(window)
    , m_window(window)
    , m_shellSurface(wl_shell_get_shell_surface(shell->shell(), window->wlSurface()))
{
    wl_shell_surface_add_listener(m_shellSurface, &kShellSurfaceListener, this);
    if (shell->extension()) {
        m_extended = qt_surface_extension_get_extended_surface(shell->extension(), window->wlSurface());
        qt_extended_surface_add_listener(m_extended, &kExtendedSurfaceListener, this);
    }
    setRole();
    if (isCoverWindow(window->window()))
        m_cover = std::make_unique<KeelCoverExposure>(window);
}

KeelShellSurface::~KeelShellSurface()
{
    if (m_extended)
        qt_extended_surface_destroy(m_extended);
    if (m_shellSurface)
        wl_shell_surface_destroy(m_shellSurface);
}

void KeelShellSurface::setRole()
{
    QWaylandWindow *parent = m_window->transientParent();
    if (!parent || !parent->wlSurface()) {
        wl_shell_surface_set_toplevel(m_shellSurface);
        return;
    }
    // Position relative to the parent, as wl_shell wants it.
    const QPoint pos = m_window->geometry().topLeft() - parent->geometry().topLeft();
    if (m_window->window()->type() == Qt::Popup) {
        QWaylandDisplay *display = m_window->display();
        if (QWaylandInputDevice *device = display->lastInputDevice()) {
            wl_shell_surface_set_popup(m_shellSurface, device->wl_seat(), display->lastInputSerial(),
                                       parent->wlSurface(), pos.x(), pos.y(), 0);
            return;
        }
    }
    const Qt::WindowFlags flags = m_window->window()->flags();
    const bool inactive = flags.testFlag(Qt::ToolTip) || flags.testFlag(Qt::WindowTransparentForInput)
            || m_window->window()->property("_q_showWithoutActivating").toBool();
    wl_shell_surface_set_transient(m_shellSurface, parent->wlSurface(), pos.x(), pos.y(),
                                   inactive ? WL_SHELL_SURFACE_TRANSIENT_INACTIVE : 0);
}

void KeelShellSurface::setOnscreenVisibility(int visibility)
{
    QWindow *window = m_window->window();
    // For Keel.Shell (cover status) and anyone else who asks.
    window->setProperty("keelOnscreenVisibility", visibility);
    qCDebug(lcKeelWlShell) << window << "onscreen visibility" << visibility;
    // Recorded only: the surface is never hidden or unexposed for it (see
    // the top of this file). Shown again (display on, back from the
    // switcher): a fresh frame, as an expose would have asked for.
    if (visibility != 0)
        window->requestUpdate();
}

class KeelShellIntegrationPlugin : public QWaylandShellIntegrationPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QWaylandShellIntegrationFactoryInterface_iid FILE "keel-wl-shell.json")

public:
    QWaylandShellIntegration *create(const QString &key, const QStringList &paramList) override
    {
        Q_UNUSED(key)
        Q_UNUSED(paramList)
        return new KeelShellIntegration;
    }
};

} // namespace QtWaylandClient

QT_END_NAMESPACE

#include "keelwlshell.moc"
