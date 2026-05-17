#include "compositor.h"

#include "foreign_toplevel_v1.h"
#include "layer_shell_v1.h"
#include "screencopy_v1.h"
#include "session_lock_v1.h"
#include "textinputv3.h"

#include <QLoggingCategory>
#include <QQuickWindow>
#include <QScreen>
#include <QWaylandXdgSurface>
#include <QWaylandXdgToplevel>

Q_LOGGING_CATEGORY(lcComp, "marathon.compositor")

namespace {
    // Reuse the env var historically set by the shell so existing tooling
    // and app-runner don't need to change.
    QByteArray defaultSocketName() {
        const QByteArray fromEnv = qgetenv("MARATHON_WL_SOCKET_NAME");
        if (!fromEnv.isEmpty())
            return fromEnv;
        return QByteArrayLiteral("marathon-wayland-0");
    }
} // namespace

MarathonCompositor::MarathonCompositor(QObject *parent)
    : QWaylandQuickCompositor(parent) {
    setSocketName(defaultSocketName());
    qCInfo(lcComp) << "socket:" << socketName();

    // Built-in QtWayland extensions parented to the compositor. Constructed
    // here (not in create()) because they self-register via
    // QWaylandCompositorExtensionTemplate when the compositor finalises —
    // matching the Qt examples. Custom raw-protocol extensions wait for
    // create() because they call wl_global_create(display(), ...) directly.
    m_xdgShell    = new QWaylandXdgShell(this);
    m_viewporter  = new QWaylandViewporter(this);
    m_textInputV2 = new QWaylandTextInputManager(this);
    m_idleInhibit = new QWaylandIdleInhibitManagerV1(this);
}

MarathonCompositor::~MarathonCompositor() = default;

void MarathonCompositor::create() {
    // Let QtWayland finish wiring the wl_display + bind the socket. Until
    // this returns, display() may be valid but the event loop integration
    // is not finalised — calling wl_global_create against it races.
    QWaylandQuickCompositor::create();

    // Custom raw-protocol extensions. All four call wl_global_create
    // against display() in their constructors; ordered so dependants come
    // last (foreign-toplevel reads m_xdgShell).
    m_textInputV3      = new TextInputManagerV3(this);
    m_layerShell       = new WlrLayerShellV1(this);
    m_sessionLock      = new ExtSessionLockManagerV1(this);
    m_foreignToplevels = new ForeignToplevelManagerV1(this);
    m_screencopy       = new ScreencopyManagerV1(this);

    // Bridge xdg-shell → foreign-toplevel-management: every new
    // xdg_toplevel gets a handle so the shell can list / activate /
    // close it from outside the compositor process.
    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated, this,
            [this](QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *) {
                m_foreignToplevels->registerToplevel(toplevel);
            });

    qCInfo(lcComp) << "ready: xdg-shell + viewporter + text-input-v2/v3 + idle-inhibit"
                   << "+ wlr-layer-shell-v1 + ext-session-lock-v1"
                   << "+ wlr-foreign-toplevel-management-v1 + wlr-screencopy-v1";
}

void MarathonCompositor::setupOutput(QWaylandQuickOutput *output) {
    if (!output) {
        qCWarning(lcComp) << "setupOutput called with null output";
        return;
    }
    // QWaylandOutput::window() returns QWindow* (the parent type); the
    // QQuickWindow downcast is safe because Compositor.qml only ever
    // declares a QtQuick Window as the WaylandOutput's window.
    auto *quickWindow = qobject_cast<QQuickWindow *>(output->window());
    if (quickWindow) {
        QScreen *screen = quickWindow->screen();
        if (screen && screen->logicalDotsPerInch() > 0) {
            const qreal  dpi = screen->logicalDotsPerInch();
            const QSize  px  = quickWindow->size();
            const QSizeF mm(px.width() / dpi * 25.4, px.height() / dpi * 25.4);
            output->setPhysicalSize(QSize(qRound(mm.width()), qRound(mm.height())));
        }
        if (m_screencopy)
            m_screencopy->setWindow(quickWindow);
    }
    if (m_screencopy)
        m_screencopy->setOutput(output);

    qCInfo(lcComp) << "output ready, screencopy wired";
}
