// marathon-compositor — standalone Wayland compositor host for Marathon-Shell.
//
// All compositor wiring lives in QML (Compositor.qml). main() just spins
// up the QML engine; the WaylandCompositor is the QML root and follows
// Qt's componentComplete lifecycle so the threaded render loop never
// sees a half-wired WaylandOutput. systemd's sd_notify is fired after
// the QML root has finished setup (deferred to next event-loop tick).

#include "compositor.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QTimer>

#ifdef MARATHON_HAVE_SD_NOTIFY
extern "C" {
#include <systemd/sd-daemon.h>
}
#endif

Q_LOGGING_CATEGORY(lcMain, "marathon.compositor.main")

int main(int argc, char *argv[]) {
    // Required when Qt Quick spans multiple GL contexts (e.g. WaylandOutput
    // for each client buffer texture). Set before constructing the app.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts, true);

    QGuiApplication::setApplicationName("Marathon Compositor");
    QGuiApplication::setOrganizationName("Marathon OS");

    QGuiApplication app(argc, argv);

    qCInfo(lcMain) << "starting";

    QQmlApplicationEngine engine;
    engine.loadFromModule("MarathonCompositor", "Compositor");
    if (engine.rootObjects().isEmpty()) {
        qCCritical(lcMain) << "failed to load Compositor.qml";
        return 1;
    }

#ifdef MARATHON_HAVE_SD_NOTIFY
    // Defer the ready notification to the next event-loop tick so the
    // socket is fully bound. QWaylandCompositor::create() runs from QML's
    // componentComplete, which has finished by the time control returns
    // to main() — but the wl_display event source isn't dispatched until
    // the event loop starts.
    QTimer::singleShot(0, [] {
        sd_notify(0, "READY=1\nSTATUS=Compositor ready, socket bound\n");
        qCInfo(lcMain) << "notified systemd READY=1";
    });
#endif

    return app.exec();
}
