#include "compositor.h"

#include "layer_shell_v1.h"
#include "session_lock_v1.h"
#include "textinputv3.h"

#include <QLoggingCategory>
#include <QQuickWindow>
#include <QScreen>

Q_LOGGING_CATEGORY(lcComp, "marathon.compositor")

namespace {
    // Reuse the env var the shell historically set so existing tooling /
    // app-runner doesn't need to change. The systemd-unit pre-Phase-C-6 will
    // export this same value to the user env so the shell (Wayland client)
    // and app-runners (also clients) find the socket without any extra plumbing.
    QByteArray defaultSocketName() {
        const QByteArray fromEnv = qgetenv("MARATHON_WL_SOCKET_NAME");
        if (!fromEnv.isEmpty())
            return fromEnv;
        return QByteArrayLiteral("marathon-wayland-0");
    }
} // namespace

MarathonCompositor::MarathonCompositor(QObject *parent)
    : QWaylandCompositor(parent) {
    const QByteArray sock = defaultSocketName();
    setSocketName(sock);
    qCInfo(lcComp) << "socket:" << sock;

    m_xdgShell   = new QWaylandXdgShell(this);
    m_viewporter = new QWaylandViewporter(this);

    m_textInputV2 = new QWaylandTextInputManager(this);

    m_idleInhibit = new QWaylandIdleInhibitManagerV1(this);

    // Custom Marathon extensions. Initialization deferred to attachWindow so
    // the wl_global creation happens after the compositor is fully alive.
    // (Qt's QWaylandCompositor finishes wiring during create()/init.)
}

MarathonCompositor::~MarathonCompositor() = default;

void MarathonCompositor::attachWindow(QQuickWindow *window) {
    if (!window) {
        qCWarning(lcComp) << "attachWindow called with null window";
        return;
    }
    m_window = window;

    m_output = new QWaylandQuickOutput;
    m_output->setCompositor(this);
    m_output->setWindow(window);
    m_output->setSizeFollowsWindow(true);
    calculatePhysicalSize();

    // Now create the custom extensions — they need the compositor to be
    // fully alive (wl_display ready, sockets bound).
    m_textInputV3 = new TextInputManagerV3(this);
    m_layerShell  = new WlrLayerShellV1(this);
    m_sessionLock = new ExtSessionLockManagerV1(this);

    qCInfo(lcComp) << "ready: xdg-shell + viewporter + text-input-v2/v3 + idle-inhibit"
                   << "+ wlr-layer-shell-v1 + ext-session-lock-v1";
}

void MarathonCompositor::calculatePhysicalSize() {
    if (!m_window || !m_output)
        return;
    // Mobile DPI assumption: report a phone-shaped physical size so
    // clients that calculate DPI from output dimensions land on
    // sensible numbers. Mirrors the original WaylandCompositor logic.
    QScreen *screen = m_window->screen();
    if (!screen)
        return;
    const qreal dpiPx = screen->logicalDotsPerInch();
    if (dpiPx <= 0)
        return;
    const QSize  px    = m_window->size();
    const QSizeF mm    = QSizeF(px.width() / dpiPx * 25.4, px.height() / dpiPx * 25.4);
    const QSize  mmInt = QSize(qRound(mm.width()), qRound(mm.height()));
    m_output->setPhysicalSize(mmInt);
}
