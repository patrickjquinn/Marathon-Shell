// marathon-compositor — the standalone Wayland compositor host for
// Marathon-Shell. Phase C-1 ships this as a minimal scaffold: it brings up
// xdg-shell + text-input v2/v3 + viewporter + idle-inhibit (Qt) plus
// zwlr_layer_shell_v1 and ext_session_lock_manager_v1 (custom). The shell
// remains the monolithic-compositor binary until C-2 swaps the wiring.
//
// Phase C-6 will wrap this as a Type=notify systemd user service; the
// sd_notify(READY=1) call below tells systemd when the wl socket is
// listening so marathon-shell.service (After= + Requires= + BindsTo=
// this) can connect without racing.

#include "compositor.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSurfaceFormat>

#ifdef MARATHON_HAVE_SD_NOTIFY
extern "C" {
#include <systemd/sd-daemon.h>
}
#endif

Q_LOGGING_CATEGORY(lcMain, "marathon.compositor.main")

int main(int argc, char *argv[]) {
    QGuiApplication::setApplicationName("Marathon Compositor");
    QGuiApplication::setOrganizationName("Marathon OS");

    QGuiApplication app(argc, argv);

    qInfo() << "Marathon compositor starting";

    MarathonCompositor compositor;
    // create() binds the wl socket and announces all globals owned by
    // QWaylandCompositor itself (xdg-shell, viewporter, text-input-v2,
    // idle-inhibit). It must run before attachWindow because our custom
    // extensions register globals against compositor->display() inside
    // attachWindow, and those wl_global_create calls were segfaulting
    // when the display wasn't fully initialised yet.
    compositor.create();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("MarathonCompositor",
                                             QVariant::fromValue(&compositor));
    engine.loadFromModule("MarathonCompositor", "Compositor");
    if (engine.rootObjects().isEmpty()) {
        qCCritical(lcMain) << "Failed to load compositor.qml";
        return 1;
    }

    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window) {
        qCCritical(lcMain) << "Root QML object is not a QQuickWindow";
        return 1;
    }
    compositor.attachWindow(window);

#ifdef MARATHON_HAVE_SD_NOTIFY
    // Tell systemd we're ready. The wl socket is bound by now
    // (QWaylandCompositor::create() returned) so the shell can connect.
    sd_notify(0, "READY=1\nSTATUS=Compositor ready, socket bound\n");
    qCInfo(lcMain) << "notified systemd READY=1";
#endif

    return app.exec();
}
