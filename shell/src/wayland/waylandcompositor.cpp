#include "src/wayland/waylandcompositor.h"
#include "src/wayland/keyrouting.h"
#include "src/wayland/keelcover.h"
#include "src/wayland/nativeback.h"
#include "marathonappregistry.h"
#include "src/wayland/committimingv1.h"
#include "src/wayland/fifov1.h"
#include "src/wayland/linuxdmabufv1.h"
#include "src/wayland/wldrm.h"
#include "src/wayland/nativeclientscale.h"
#include "src/wayland/securitycontextv1.h"
#include "src/wayland/xdgactivationv1.h"
#include "src/wayland/marathonsurfacev1.h"
#include "src/wayland/toplevelconfigure.h"
#include "marathon-surface-v1-server.h"
#include "src/components/windowtextureitem.h"
#include "src/managers/deviceprofile.h"
#include "src/services/processtree.h"
#include "marathon-shell-native/src/desktop.cxxqt.h"
#include <QDebug>
#include <QTimer>
#include <QPointer>
#include <QDateTime>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QCoreApplication>
#include <QWaylandXdgToplevel>
#include <QWaylandXdgSurface>
#include <QWaylandXdgPopup>
#include <QWaylandQuickItem>
#include <QWaylandQuickSurface>
#include <QWaylandView>
#include <QtMath>
#include <QQmlEngine>
#include <QQuickItem>
#include <QKeyEvent>
#include <QScreen>
#include <QGuiApplication>
#include <qpa/qplatformnativeinterface.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <cstring>
#include <wayland-server-core.h>

#include "util/frametiming.h"
#include "util/rtprio.h"
#include <algorithm>
#include <utility>   // std::as_const

static bool envBool(const char *name, bool defaultValue) {
    const QByteArray raw = qgetenv(name);
    if (raw.isEmpty()) {
        return defaultValue;
    }
    const QByteArray valueString = raw.trimmed().toLower();
    if (valueString == "1" || valueString == "true" || valueString == "yes" ||
        valueString == "on") {
        return true;
    }
    if (valueString == "0" || valueString == "false" || valueString == "no" ||
        valueString == "off") {
        return false;
    }
    return defaultValue;
}

static bool wlVerbose() {
    return envBool("MARATHON_WL_VERBOSE", false);
}

static bool appLogsEnabled() {
    // Default ON. Without app logs in journald, browser/maps/etc cold-start
    // hangs are undebuggable — the audit lost 6 minutes diagnosing a WebEngine
    // ZINK init failure that was already in stderr but nobody was reading it.
    // Set MARATHON_APP_LOGS=0 to silence in performance-critical builds.
    return envBool("MARATHON_APP_LOGS", true);
}

static bool appLogsAllEnabled() {
    return envBool("MARATHON_APP_LOGS_ALL", false);
}

WaylandCompositor::WaylandCompositor(QQuickWindow *window)
    : m_window(window)
    , m_nextSurfaceId(1)
    , m_output(nullptr)
    , m_hasIdleInhibitor(false) {

    const QByteArray socketNameEnv = qgetenv("MARATHON_WL_SOCKET_NAME").trimmed();
    const QByteArray socketNameBytes =
        socketNameEnv.isEmpty() ? QByteArrayLiteral("marathon-wayland-0") : socketNameEnv;
    setSocketName(socketNameBytes);

    QList<QWaylandCompositor::ShmFormat> shmFormats;
    shmFormats << QWaylandCompositor::ShmFormat_ARGB8888;
    shmFormats << QWaylandCompositor::ShmFormat_XRGB8888;
    setAdditionalShmFormats(shmFormats);

    create();

    m_xdgShell               = new QWaylandXdgShell(this);
#ifdef HAVE_WAYLAND_PRIVATE
    // Qt's xdg-shell activates the toplevel with keyboard focus (and resends
    // on every focus loss). A client the shell did not launch keeps the state
    // of its first configure: Waydroid re-plugs Android's display on every
    // configure, and one racing a keyboard enter deadlocks Android. Qt's slot
    // is private, so its connections from the seat are dropped once it has
    // made them (the shell initializes on Polish).
    QMetaObject::invokeMethod(
        this,
        [this]() {
            if (!disconnect(defaultSeat(),
                            SIGNAL(keyboardFocusChanged(QWaylandSurface *, QWaylandSurface *)),
                            m_xdgShell, nullptr))
                qWarning() << "[WaylandCompositor] xdg-shell focus handling not replaced";
            connect(defaultSeat(), &QWaylandSeat::keyboardFocusChanged, this,
                    [this](QWaylandSurface *newFocus, QWaylandSurface *oldFocus) {
                        for (QWaylandSurface *surface : {newFocus, oldFocus}) {
                            if (!surface || surface->property("foreignClient").toBool())
                                continue;
                            const QWaylandXdgSurface *xdg =
                                m_xdgSurfaceMap.value(surface->property("surfaceId").toInt());
                            if (xdg && xdg->toplevel())
                                ToplevelConfigure::setActivated(xdg->toplevel(),
                                                                surface == newFocus);
                        }
                    });
        },
        Qt::QueuedConnection);
#endif
    QMetaObject::invokeMethod(
        this,
        [this]() {
            connect(defaultSeat(), &QWaylandSeat::keyboardFocusChanged, this,
                    [this]() { m_keyboardFocusSince.start(); });
        },
        Qt::QueuedConnection);
    const bool enableWlShell = envBool("MARATHON_WL_ENABLE_WL_SHELL", false);
    if (enableWlShell) {
        m_wlShell = new QWaylandWlShell(this);
        connect(m_wlShell, &QWaylandWlShell::wlShellSurfaceCreated, this,
                &WaylandCompositor::handleWlShellSurfaceCreated);
        qInfo() << "[WaylandCompositor] wl_shell enabled (legacy compatibility)";
    } else {
        qInfo() << "[WaylandCompositor] wl_shell disabled (legacy protocol)";
    }

    const bool enableViewporter  = envBool("MARATHON_WL_ENABLE_VIEWPORTER", true);
    const bool enableTextInputV2 = envBool("MARATHON_WL_ENABLE_TEXT_INPUT_V2", true);
    const bool enableIdleInhibit = envBool("MARATHON_WL_ENABLE_IDLE_INHIBIT", true);

    if (enableViewporter) {
        m_viewporter = new QWaylandViewporter(this);
        qInfo() << "[WaylandCompositor] wp_viewporter enabled";
    } else {
        qInfo() << "[WaylandCompositor] wp_viewporter disabled";
    }

    if (enableTextInputV2) {
        m_textInputManager = new QWaylandTextInputManager(this);
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 enabled";
    } else {
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 disabled";
    }

    // Qt's text-input-v3 carries the keyboard's commits to GTK and other v3
    // clients. Keyboard show/hide follows their enable/disable requests (see
    // connectTextInputs()).
    m_textInputManagerV3 = new QWaylandTextInputManagerV3(this);
    watchTextInputBinds();

    m_securityContextManager = new SecurityContextManagerV1(this);

    // Nothing the shell draws covers a window: it is laid out between the
    // status area and the pill, and resized for the keyboard.
    m_marathonSurfaceManager = new MarathonSurfaceManagerV1(this, m_securityContextManager);
    connect(m_marathonSurfaceManager, &MarathonSurfaceManagerV1::surfaceAdded, this,
            [this](MarathonSurfaceV1 *marathon) {
                QWaylandSurface *surface = marathon->surface();
                if (surface->property("toplevelMapped").toBool() &&
                    marathon->sendInsets(QMargins(), 0))
                    nudgeSurface(surface->property("surfaceId").toInt());
                emit marathonSurfacesChanged();
            });
    connect(m_marathonSurfaceManager, &MarathonSurfaceManagerV1::surfaceRemoved, this,
            &WaylandCompositor::marathonSurfacesChanged);

    // wp_fifo_v1 — queued-presentation barriers. Surfaces with
    // set_barrier / wait_barrier get FIFO ordering enforced at the
    // Qt scene-graph swap boundary (QQuickWindow::frameSwapped). Apps
    // that bind this protocol (SDL3, Chromium Ozone, future Mesa
    // presentation loop) get the strict frame-N-before-N+1 guarantee
    // they need for jank-free animation.
    m_fifoManager = new FifoManagerV1(this, window);

    // wp_commit_timing_v1 — per-commit presentation timestamps. Pairs
    // with fifo-v1 to give clients (SDL3, Chromium, Mesa) the
    // deadline-driven scheduling primitives they prefer for animation.
    // Tracked but not yet enforced at present time — see committimingv1.h
    // for the honesty note on the public-API constraint.
    m_commitTimingManager = new CommitTimingManagerV1(this);

    // zwp_linux_dmabuf_v1 v4 — Marathon's own implementation that
    // advertises the v4 feedback layer (main_device + tranche_*) on
    // top of Qt's existing v3 plugin. Chromium binds the higher
    // version for feedback events; Qt's v3 plugin handles actual buffer
    // import. See linuxdmabufv1.h for the scope honesty and the
    // hypothesis the spike is testing.
    m_linuxDmabufManager = new LinuxDmabufManagerV1(this);

    // wl_drm — device discovery for Mesa's wayland-egl clients (apps). Qt's
    // v3 dmabuf carries no render-device identity and the v4 feedback global
    // above is gated off (it breaks Qt buffer import), so on Mesa 26.1.1 app
    // clients can't find the etnaviv render node and drop to llvmpipe. wl_drm
    // names /dev/dri/renderD128 + advertises PRIME so Mesa renders on etnaviv
    // while buffers still import through Qt's v3 dmabuf. See wldrm.h.
    m_wlDrmManager = new WlDrmManager(this);

    m_xdgActivation = new XdgActivationV1(this);
    connect(m_xdgActivation, &XdgActivationV1::activated, this,
            &WaylandCompositor::handleActivation);

    m_nativeClientScale = new NativeClientScale(this);
    connect(m_nativeClientScale, &NativeClientScale::scaleChanged, this,
            &WaylandCompositor::nativeScaleChanged);
    wl_display_set_global_filter(static_cast<wl_display *>(display()),
                                 &WaylandCompositor::filterGlobal, this);

    if (enableIdleInhibit) {
        m_idleInhibitManager = new QWaylandIdleInhibitManagerV1(this);
        qInfo() << "[WaylandCompositor] zwp_idle_inhibit_manager_v1 enabled";
    } else {
        qInfo() << "[WaylandCompositor] zwp_idle_inhibit_manager_v1 disabled";
    }
    // Note: wp_presentation (QWaylandPresentationTime) is intentionally NOT
    // wired up here. Qt 6.10.2 on Fedora exposes the class only via private
    // headers; using it would tie Marathon to Qt's private API. Re-add when
    // either (a) we standardize on a Qt version with the public class, or
    // (b) we decide the private-header dependency is acceptable.

    connect(defaultSeat(), &QWaylandSeat::keyboardFocusChanged, this,
            [this](QWaylandSurface *newFocus, QWaylandSurface *oldFocus) {
                Q_UNUSED(oldFocus);
                if (wlVerbose() && newFocus)
                    qDebug() << "[WaylandCompositor] Keyboard focus changed to surface:"
                             << newFocus;
                // A different app took focus: drop the keyboard. Qt clients
                // stay "enabled" after their field is gone, so showing here
                // opened it over apps with no field focused. An app that
                // wants it asks again: GTK re-enables on enter, Qt clients on
                // the next field tap (see marathoninputcontext.cpp). With no
                // client focused, the shell's own fields own the panel.
                if (newFocus)
                    emit nativeTextInputPanelRequested(false);
            });

    // Create QWaylandQuickSurface, not the default plain QWaylandSurface.
    // Qt's QtQuick render path (QWaylandSurfaceTextureProvider::setBufferRef in
    // qwaylandquickitem.cpp) does `qobject_cast<QWaylandQuickSurface*>(surface)`
    // and then dereferences the result UNCONDITIONALLY on the hardware-buffer
    // path (`surface->bufferSize()`), guarded only for the useTextureAlpha
    // branch. With the base QWaylandCompositor's createDefaultSurface() handing
    // back a plain QWaylandSurface, that cast is always null, so the first GPU
    // (dmabuf) frame segfaults the compositor in QWaylandSurface::bufferSize.
    // Shared-memory clients took the image() path and never hit it, which is
    // why this only surfaced once apps began rendering through dmabuf. Handling
    // surfaceRequested is the standard pattern for a QtQuick compositor built on
    // the non-quick QWaylandCompositor base; the surface auto-registers via its
    // initialize() in the constructor, and Qt owns it through the wl_surface
    // resource lifecycle exactly as createDefaultSurface() would.
    connect(this, &QWaylandCompositor::surfaceRequested, this,
            [this](QWaylandClient *client, uint id, int version) {
                auto *surface = new QWaylandQuickSurface(this, client, id, version);
                // Parentless, so a surface handed to QML (getSurfaceById)
                // became the JS engine's to collect. A collected surface
                // took its xdg_surface with it, and the client's next
                // set_window_geometry crashed the compositor.
                QQmlEngine::setObjectOwnership(surface, QQmlEngine::CppOwnership);
            });

    connect(this, &QWaylandCompositor::surfaceCreated, this,
            &WaylandCompositor::handleSurfaceCreated);

    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated, this,
            &WaylandCompositor::handleXdgToplevelCreated);
    connect(m_xdgShell, &QWaylandXdgShell::popupCreated, this,
            &WaylandCompositor::handleXdgPopupCreated);

    m_output = new QWaylandQuickOutput(this, window);
    m_output->setSizeFollowsWindow(true);

    setDefaultOutput(m_output);

    calculateAndSetPhysicalSize();

    qInfo() << "[WaylandCompositor] Initialized on socket:" << socketName()
            << "output:" << window->size() << "(scale=" << m_output->scaleFactor() << ")";

    setCompositorRealtimePriority();

    // ── Present pipeline (opt-out: MARATHON_PRESENT_PIPELINE=0) ───────
    // Default QtWayland throttles client scroll to ~15fps on this in-process
    // compositor: it sends wl_surface.frame callbacks from afterRendering
    // (frame END, cross-thread-queued to the GUI loop) and the on-demand
    // threaded render loop sleeps between frames, so a client's commit waits
    // ~1 vblank to be scheduled and its callback arrives only after our frame
    // -- a serialized ~4-vblank round trip (measured: client swap blocks
    // ~67ms, both sides idle). This collapses it to a 1-frame pipeline.
    m_presentPipeline = envBool("MARATHON_PRESENT_PIPELINE", true);
    if (m_presentPipeline && m_window && m_output) {
        m_output->setAutomaticFrameCallback(false);
        m_hiddenThrottle = envBool("MARATHON_HIDDEN_THROTTLE", true);
        m_frameClock.start();
        m_hiddenFrameTimer.setSingleShot(true);
        m_hiddenFrameTimer.setInterval(int(m_frameThrottle.interval()));
        connect(&m_hiddenFrameTimer, &QTimer::timeout, this,
                [this]() { sendPacedFrameCallbacks(true); });
        // beforeSynchronizing runs on the render thread while the GUI thread
        // is blocked in sync -- the safe point to touch wl_display. Sending
        // the frame callback here (frame START, before our own present) hands
        // the client the full frame interval to render its next buffer
        // concurrently, instead of only after our frame completes.
        bool phaseSet  = false;
        m_framePhaseMs = qEnvironmentVariableIntValue("MARATHON_FRAME_PHASE_MS", &phaseSet);
        if (!phaseSet)
            m_framePhaseMs = 8;
        if (m_framePhaseMs > 0) {
            // Frames latch late in the vblank interval and clients hear at the
            // vblank, so a client's frame lands in the next composite.
            m_gateTimer.setSingleShot(true);
            m_gateTimer.setTimerType(Qt::PreciseTimer);
            connect(&m_gateTimer, &QTimer::timeout, this, [this]() {
                m_passUpdate = true;
                QCoreApplication::postEvent(m_window, new QEvent(QEvent::UpdateRequest));
            });
            m_callbackTimer.setSingleShot(true);
            m_callbackTimer.setTimerType(Qt::PreciseTimer);
            connect(&m_callbackTimer, &QTimer::timeout, this, [this]() { sendPacedFrameCallbacks(false); });
            connect(
                m_window, &QQuickWindow::beforeSynchronizing, this,
                [this]() {
                    QMetaObject::invokeMethod(
                        this,
                        [this]() {
                            const qint64 next = nextVblankUs();
                            m_callbackTimer.start(next < 0 ? 0 : int(qMax<qint64>(0, next - monotonicUs()) / 1000));
                        },
                        Qt::QueuedConnection);
                },
                Qt::DirectConnection);
        } else {
            connect(
                m_window, &QQuickWindow::beforeSynchronizing, this,
                [this]() { sendPacedFrameCallbacks(false); }, Qt::DirectConnection);
        }
        qInfo() << "[WaylandCompositor] Present pipeline ENABLED (early frame callbacks), phase" << m_framePhaseMs;
    }

    // Opt-in (MARATHON_PRESENT_FREERUN): unthrottled where swap doesn't block
    // on vblank (software backend, Xvfb): ~3 compositor frames per commit.
    m_presentFreeRun = m_presentPipeline && envBool("MARATHON_PRESENT_FREERUN", false);
    if (m_presentFreeRun) {
        // While a client is actively committing, free-run the on-demand loop
        // at vsync so its just-committed buffer composites on the very next
        // vblank instead of the scheduler sleeping and missing it. Credits are
        // refreshed on every client commit (redraw) and decay to 0 when
        // commits stop -> compositor idles back to 0fps (preserves Doze).
        connect(
            m_window, &QQuickWindow::frameSwapped, this,
            [this]() {
                const int c = m_activeFrameCredits.loadRelaxed();
                if (c > 0) {
                    m_activeFrameCredits.storeRelaxed(c - 1);
                    QMetaObject::invokeMethod(
                        m_window, [w = m_window]() { w->update(); }, Qt::QueuedConnection);
                }
            },
            Qt::DirectConnection);
        qInfo() << "[WaylandCompositor] Present free-run ENABLED (commit-gated vsync)";
    }

    m_discardFrontBuffer = envBool("MARATHON_DISCARD_FRONT", false);
    if (m_discardFrontBuffer)
        qInfo() << "[WaylandCompositor] Front-buffer discard ENABLED (eager client "
                   "buffer release)";

    if (envBool("MARATHON_FRAME_TIMING", false)) {
        marathon::diag::installFrameTimingTracker(m_window, QStringLiteral("compositor"));
        qInfo() << "[WaylandCompositor] Frame-timing diagnostics enabled";
    }

    // ── Present stats (opt-in: MARATHON_PRESENT_STATS) ───────────────
    // One log line per second: compositor frames + client commits. Cheap
    // enough not to backpressure the log pipe (unlike QSG_RENDER_TIMING),
    // so scroll rate stays measurable while the meter is on.
    if (envBool("MARATHON_PRESENT_STATS", false) && m_window) {
        connect(
            m_window, &QQuickWindow::frameSwapped, this,
            [this]() { m_frameSwapCount.fetchAndAddRelaxed(1); }, Qt::DirectConnection);
        auto *statsTimer = new QTimer(this);
        statsTimer->setInterval(1000);
        connect(statsTimer, &QTimer::timeout, this, [this]() {
            const int frames  = m_frameSwapCount.fetchAndStoreRelaxed(0);
            const int commits = m_clientCommitCount.fetchAndStoreRelaxed(0);
            // qWarning, not qInfo: release builds define QT_NO_INFO_OUTPUT,
            // which compiled this meter out of exactly the images worth
            // measuring. The env gate above already makes it opt-in, so it
            // is never noise.
            qWarning().nospace() << "[PresentStats] compositor=" << frames
                                 << "fps client_commits=" << commits << "/s";
        });
        statsTimer->start();
        qInfo() << "[WaylandCompositor] Present stats ENABLED (1Hz compositor/client "
                   "rate meter)";
    }

    m_window->installEventFilter(this);

    // Dev helper, opt-in: a stray binary must not launch on a user's phone.
    if (qEnvironmentVariableIntValue("MARATHON_AUTOLAUNCH_DEBUG_APP") == 1) {
        QTimer::singleShot(15000, this, [this]() {
            if (QFile::exists("/usr/bin/marathon-app-debug"))
                launchApp("/usr/bin/marathon-app-debug");
        });
    }
}

WaylandCompositor::~WaylandCompositor() {
    wl_display_set_global_filter(static_cast<wl_display *>(display()), nullptr, nullptr);
    // keyBegin/keyEnd, not keys(): the latter allocates an entire QList
    // just to walk it once, in a destructor.
    for (auto it = m_processes.keyBegin(), end = m_processes.keyEnd(); it != end; ++it) {
        QProcess *process = *it;
        if (process->state() != QProcess::NotRunning) {
            process->terminate();
            if (!process->waitForFinished(3000)) {
                process->kill();
            }
        }
        process->deleteLater();
    }
}

bool WaylandCompositor::filterGlobal(const wl_client *client, const wl_global *global, void *data) {
    auto *self = static_cast<WaylandCompositor *>(data);
    return self->m_securityContextManager->allowsGlobal(client, global) &&
        self->m_nativeClientScale->allowsGlobal(client, global) &&
        self->m_marathonSurfaceManager->allowsGlobal(client, global);
}

QString WaylandCompositor::openSandboxSocket(const QString &appId, const QString &instanceId) {
    const QString dir =
        qEnvironmentVariable("XDG_RUNTIME_DIR") + QStringLiteral("/marathon-sandbox");
    if (!QDir().mkpath(dir))
        return {};
    QString path = dir + QLatin1Char('/') + instanceId;
    if (!m_securityContextManager->listen(
            path, {QStringLiteral("org.marathonos.AppRunner"), appId, instanceId}))
        return {};
    return path;
}

void WaylandCompositor::closeSandboxSocket(const QString &instanceId) {
    m_securityContextManager->closeListener(instanceId);
}

void WaylandCompositor::assignSandboxApp(const QString &instanceId, const QString &appId) {
    m_securityContextManager->assignAppId(instanceId, appId);
}

QString WaylandCompositor::sandboxAppId(wl_client *client) const {
    return m_securityContextManager->contextForClient(client).appId;
}

QQmlListProperty<QObject> WaylandCompositor::surfaces() {
    return QQmlListProperty<QObject>(this, &m_surfaces);
}

void WaylandCompositor::launchApp(const QString &command, const QVariantMap &extraEnv) {
    if (!command.isEmpty()) {
        qDebug() << "[WaylandCompositor] Launching app:" << command;
        qDebug() << "[WaylandCompositor] Socket name:" << socketName();
        qDebug() << "[WaylandCompositor] XDG_RUNTIME_DIR:" << qgetenv("XDG_RUNTIME_DIR");
    }

    QString     actualCommand = command;
    bool        isFlatpak     = command.startsWith("FLATPAK:");
    bool        isSnap        = command.startsWith("SNAP:");
    QStringList execPartsOverride;

    if (isFlatpak) {
        actualCommand = command.mid(8);
    } else if (command.startsWith("flatpak run")) {
        isFlatpak = true;
    }

    if (isSnap) {
        actualCommand = command.mid(5);
    } else if (command.startsWith("snap run")) {
        isSnap = true;
    }

    if (isFlatpak) {
        const QStringList parts = QProcess::splitCommand(actualCommand);
        if (parts.size() >= 2 && parts.at(0) == "flatpak" && parts.at(1) == "run") {
            QStringList newParts;
            // Flatpak takes WAYLAND_DISPLAY from the environment below and
            // connects the app through a security-context socket of its own.
            newParts << "flatpak"
                     << "run"
                     << "--socket=wayland";
            newParts << parts.mid(2);
            execPartsOverride = newParts;
            actualCommand     = newParts.join(' ');
        } else {
            qWarning()
                << "[WaylandCompositor] FLATPAK: command did not look like 'flatpak run ...':"
                << actualCommand;
        }
        qInfo() << "[WaylandCompositor] Flatpak command (Wayland socket injected):"
                << actualCommand;
    }

    if (isSnap) {
        qInfo() << "[WaylandCompositor] Snap app - wayland interface should be connected";
        qInfo() << "[WaylandCompositor] Run 'snap connections APP' to verify wayland interface";
    }

    QProcess           *process = new QProcess(this);

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (auto it = extraEnv.constBegin(); it != extraEnv.constEnd(); ++it) {
        env.insert(it.key(), it.value().toString());
    }
    const QString activationToken = m_xdgActivation->issueToken(process);
    env.insert("XDG_ACTIVATION_TOKEN", activationToken);
    env.insert("DESKTOP_STARTUP_ID", activationToken);
    QString runtimeDir = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR"));

    if (runtimeDir.isEmpty()) {
        qWarning() << "[WaylandCompositor] XDG_RUNTIME_DIR not set! Apps may fail to connect.";
        runtimeDir = "/tmp";
    }

    env.remove("WAYLAND_DISPLAY");
    env.remove("DISPLAY");

    // Shell-only startup shortcuts (main.cpp, marathon-shell-session): apps
    // may ship +locale QML variants, and keep their own GStreamer registries.
    env.remove("QT_NO_BUILTIN_SELECTORS");
    env.remove("GST_REGISTRY_UPDATE");

    const bool isRunner = actualCommand.contains("marathon-app-runner");

    qint64     timestamp   = QDateTime::currentMSecsSinceEpoch();
    uint       commandHash = qHash(actualCommand);

    if (!isFlatpak && !isRunner) {
        QDir tmpDir("/tmp/marathon-apps");
        if (!tmpDir.exists()) {
            tmpDir.mkpath(".");
        }

        QString uniqueDesktopFile =
            QString("/tmp/marathon-apps/marathon-%1-%2.desktop").arg(timestamp).arg(commandHash);

        QFile desktopFile(uniqueDesktopFile);
        if (desktopFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&desktopFile);
            out << "[Desktop Entry]\n";
            out << "Version=1.0\n";
            out << "Type=Application\n";
            out << "Name=Marathon Embedded App\n";
            out << "GenericName=Application\n";
            out << "Comment=Application running in Marathon OS\n";
            out << "Exec=" << actualCommand << "\n";
            out << "Terminal=false\n";
            out << "Categories=Utility;\n";
            out << "StartupNotify=true\n";
            out << "X-GNOME-UsesNotifications=false\n";
            out << "X-Marathon-Embedded=true\n";
            desktopFile.close();

            qDebug()
                << "[WaylandCompositor] Created desktop file with full specification compliance";
        } else {
            qWarning() << "[WaylandCompositor] Failed to create desktop file:" << uniqueDesktopFile;
        }

        env.insert("GIO_LAUNCHED_DESKTOP_FILE", uniqueDesktopFile);
        env.insert("GIO_LAUNCHED_DESKTOP_FILE_PID",
                   QString::number(QCoreApplication::applicationPid()));
        process->setProperty("marathonDesktopFile", uniqueDesktopFile);

        qDebug() << "[WaylandCompositor] Created unique desktop file:" << uniqueDesktopFile;
    }

    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");
    env.insert("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");
    // Apps default to the GPU scenegraph; opt back to SHM/software per-board.
    if (envBool("MARATHON_APPS_FORCE_SOFTWARE", false))
        env.insert("QT_QUICK_BACKEND", "software");

    qDebug() << "[WaylandCompositor] Setting WAYLAND_DISPLAY=" << socketName()
             << "for child process";

    {
        const QByteArray debugEnv = qgetenv("MARATHON_DEBUG").trimmed().toLower();
        const bool       debug    = (debugEnv == "1" || debugEnv == "true");
        if (debug) {
            env.insert("QT_FORCE_STDERR_LOGGING", "1");
        }
    }
    const bool forceShm      = envBool("MARATHON_FORCE_WAYLAND_SHM", false);
    const bool appsUseVulkan = envBool("MARATHON_APPS_USE_VULKAN", false);
    QString    rhiBackend    = env.value("QSG_RHI_BACKEND").trimmed().toLower();
    QString    quickBackend  = env.value("QT_QUICK_BACKEND").trimmed().toLower();
    bool       usingVulkan   = (rhiBackend == "vulkan") || (quickBackend == "vulkan");
    if (isRunner && usingVulkan && !appsUseVulkan) {
        env.insert("QSG_RHI_BACKEND", "opengl");
        env.remove("QT_QUICK_BACKEND");
        usingVulkan = false;
        rhiBackend  = QStringLiteral("opengl");
        quickBackend.clear();
        qInfo()
            << "[WaylandCompositor] App runner forced to OpenGL (set MARATHON_APPS_USE_VULKAN=1 "
               "to override)";
    }
    if (!env.contains("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION")) {
        if (forceShm) {
            env.insert("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "shm");
        } else if (!usingVulkan) {
            env.insert("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "wayland-egl");
        }
    }

    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    env.insert("MOZ_ENABLE_WAYLAND", "1");

    env.insert("QT_IM_MODULE", "wayland");
    // GTK 4 otherwise falls back to its "simple" module, never binds
    // text-input, and the keyboard can't open or type into GTK apps.
    env.insert("GTK_IM_MODULE", "wayland");
    env.insert("ELECTRON_OZONE_PLATFORM_HINT", "wayland");

    env.insert("LIBADWAITA_MOBILE", "1");
    env.insert("PURISM_FORM_FACTOR", "phone");
    env.insert("QT_QUICK_CONTROLS_MOBILE", "1");
    env.insert("QT_QUICK_CONTROLS_STYLE", "Basic");
    env.insert("GTK_CSD", "1");
    if (!env.contains("GTK_USE_PORTAL")) {
        const bool enablePortals = isFlatpak || envBool("MARATHON_ENABLE_PORTALS", false);
        env.insert("GTK_USE_PORTAL", enablePortals ? "1" : "0");
    }

    env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");

    env.insert("QT_MEDIA_BACKEND", "ffmpeg");

    if (actualCommand.contains("marathon-app-runner") || marathon::desktop::is_keel_hosted(actualCommand)) {
        env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));
    }

    process->setProcessEnvironment(env);

    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Launching:" << command;

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred, this, &WaylandCompositor::handleProcessError);

    process->setProcessChannelMode(QProcess::SeparateChannels);
    process->setProperty("marathonStdoutTail", QString());
    process->setProperty("marathonStderrTail", QString());

    QPointer<QProcess> safeProcess(process);
    const QString      logTag = command.section(QStringLiteral("--app-id "), -1).section(' ', 0, 0);
    connect(process, &QProcess::readyReadStandardOutput, this, [safeProcess, command, logTag]() {
        if (!safeProcess)
            return;
        QString output = QString::fromLocal8Bit(safeProcess->readAllStandardOutput());
        if (!output.isEmpty()) {
            QString tail = safeProcess->property("marathonStdoutTail").toString();
            tail += output;
            if (tail.size() > qsizetype{64} * 1024)
                tail = tail.right(qsizetype{64} * 1024);
            safeProcess->setProperty("marathonStdoutTail", tail);

            if (wlVerbose() && !output.trimmed().isEmpty())
                qDebug() << "[WaylandCompositor] stdout:" << command << "->" << output.trimmed();

            if (appLogsEnabled() && command.contains("marathon-app-runner") &&
                !output.trimmed().isEmpty()) {
                const QStringList lines = output.split('\n');
                int               shown = 0;
                for (const QString &l : lines) {
                    const QString line = l.trimmed();
                    if (line.isEmpty())
                        continue;
                    if (!appLogsAllEnabled()) {
                        if (line.startsWith("libEGL warning") || line.startsWith("MESA-LOADER:"))
                            continue;
                    }
                    qInfo().noquote() << "[AppRunner stdout]" << logTag << "->" << line;
                    if (++shown >= 25)
                        break;
                }
            }
        }
    });

    connect(process, &QProcess::readyReadStandardError, this, [safeProcess, command, logTag]() {
        if (!safeProcess)
            return;
        QString error = QString::fromLocal8Bit(safeProcess->readAllStandardError());
        if (!error.isEmpty()) {
            QString tail = safeProcess->property("marathonStderrTail").toString();
            tail += error;
            if (tail.size() > qsizetype{64} * 1024)
                tail = tail.right(qsizetype{64} * 1024);
            safeProcess->setProperty("marathonStderrTail", tail);

            if (wlVerbose() && !error.trimmed().isEmpty())
                qDebug() << "[WaylandCompositor] stderr:" << command << "->" << error.trimmed();

            if (appLogsEnabled() && command.contains("marathon-app-runner") &&
                !error.trimmed().isEmpty()) {
                const QStringList lines = error.split('\n');
                int               shown = 0;
                for (const QString &l : lines) {
                    const QString line = l.trimmed();
                    if (line.isEmpty())
                        continue;
                    if (!appLogsAllEnabled()) {
                        if (line.startsWith("libEGL warning") || line.startsWith("MESA-LOADER:"))
                            continue;
                    }
                    qInfo().noquote() << "[AppRunner stderr]" << logTag << "->" << line;
                    if (++shown >= 25)
                        break;
                }
            }
        }
    });

    m_processes[process] = actualCommand;

    if (wlVerbose()) {
        qDebug() << "[WaylandCompositor] Starting process:" << actualCommand;
    }

    const QStringList parts =
        execPartsOverride.isEmpty() ? QProcess::splitCommand(actualCommand) : execPartsOverride;
    const bool        hasParts = !parts.isEmpty();
    const QString     program  = hasParts ? parts.first() : QString();
    const QStringList args     = hasParts ? parts.mid(1) : QStringList();

    const bool        needsShell = !hasParts || actualCommand.contains('|') ||
        actualCommand.contains('&') || actualCommand.contains(';') ||
        actualCommand.contains("&&") || actualCommand.contains("||") ||
        actualCommand.contains('>') || actualCommand.contains('<');

    connect(process, &QProcess::started, this, [this, command, process]() {
        const qint64 pid = process ? process->processId() : -1;
        if (pid > 0) {
            qInfo() << "[WaylandCompositor] Started PID" << pid;
            emit appLaunched(command, static_cast<int>(pid));
        }
    });

    if (needsShell) {
        process->start("/bin/sh", {"-c", actualCommand});
        return;
    }
    process->setProgram(program);
    process->setArguments(args);
    process->start();
}

void WaylandCompositor::closeWindow(int surfaceId) {
    if (!m_surfaceMap.contains(surfaceId)) {
        qWarning() << "[WaylandCompositor] closeWindow called for unknown surface ID:" << surfaceId;
        return;
    }

    QWaylandSurface *surface = m_surfaceMap[surfaceId];
    if (!surface) {
        qWarning() << "[WaylandCompositor] Surface is null for ID:" << surfaceId;
        return;
    }

    // A Keel app under marathon-keel-host is closed by its host: SIGTERM is
    // keel-shell's close (PROTOCOL.md section 4). Closed itself, the app's
    // window would go and the app would stay behind its cover.
    const qint64 clientPid = m_surfaceIdToPid.value(surfaceId, -1);
    for (auto it = m_processes.cbegin(); it != m_processes.cend(); ++it) {
        QPointer<QProcess> host(it.key());
        if (!marathon::desktop::is_keel_hosted(it.value()) || host->state() == QProcess::NotRunning ||
            !isDescendantPid(clientPid, host->processId()))
            continue;
        qInfo() << "[WaylandCompositor] Closing hosted app via its Keel host, PID"
                << host->processId();
        host->setProperty("marathonCloseRequested", true);
        host->terminate();
        QTimer::singleShot(5000, this, [host]() {
            if (host && host->state() != QProcess::NotRunning) {
                host->setProperty("marathonForceKilled", true);
                host->kill();
            }
        });
        return;
    }

    QWaylandXdgSurface *xdgSurface = m_xdgSurfaceMap.value(surfaceId, nullptr);
    if (xdgSurface && xdgSurface->toplevel()) {
        qInfo()
            << "[WaylandCompositor] Sending graceful close request (XDG protocol) to surface ID:"
            << surfaceId;
        xdgSurface->toplevel()->sendClose();
    } else {
        QWaylandClient *client = surface->client();
        if (client) {
            qWarning() << "[WaylandCompositor] No XDG toplevel found, falling back to client close "
                          "for surface ID:"
                       << surfaceId;
            client->close();
        }
    }

    qint64 pid = m_surfaceIdToPid.value(surfaceId, -1);
    if (pid <= 0) {
        qDebug() << "[WaylandCompositor] No PID mapping for surface ID:" << surfaceId;
        return;
    }

    QProcess *targetProcess = nullptr;
    for (auto it = m_processes.begin(); it != m_processes.end(); ++it) {
        QProcess *process = it.key();
        if (process && process->processId() == pid) {
            targetProcess = process;
            break;
        }
    }

    if (!targetProcess) {
        qDebug() << "[WaylandCompositor] No process found for PID:" << pid;
        return;
    }

    targetProcess->setProperty("marathonCloseRequested", true);

    QPointer<QProcess> safeProcessPtr(targetProcess);

    qDebug() << "[WaylandCompositor] Waiting for PID" << pid << "to exit gracefully...";
    QTimer::singleShot(5000, this, [this, safeProcessPtr, surfaceId, pid]() {
        if (!safeProcessPtr) {
            qInfo() << "[WaylandCompositor] Process" << pid
                    << "exited gracefully (object deleted) for surface ID:" << surfaceId;
            return;
        }

        if (safeProcessPtr->state() != QProcess::NotRunning) {
            qWarning() << "[WaylandCompositor] Process" << pid
                       << "didn't exit after 5s, sending SIGTERM";
            safeProcessPtr->setProperty("marathonForceTerminated", true);
            safeProcessPtr->terminate();

            QTimer::singleShot(3000, this, [safeProcessPtr, pid]() {
                if (safeProcessPtr && safeProcessPtr->state() != QProcess::NotRunning) {
                    qWarning() << "[WaylandCompositor] Force killing process" << pid;
                    safeProcessPtr->setProperty("marathonForceKilled", true);
                    safeProcessPtr->kill();
                }
            });
        } else {
            qInfo() << "[WaylandCompositor] Process" << pid
                    << "exited gracefully for surface ID:" << surfaceId;
        }
    });
}

QObject *WaylandCompositor::getSurfaceById(int surfaceId) {
    return m_surfaceMap.value(surfaceId, nullptr);
}

QObject *WaylandCompositor::shellSurfaceById(int surfaceId) {
    QObject *xdg = m_xdgSurfaceMap.value(surfaceId, nullptr);
    if (xdg)
        QQmlEngine::setObjectOwnership(xdg, QQmlEngine::CppOwnership);
    return xdg ? xdg : m_surfaceMap.value(surfaceId, nullptr);
}

namespace {

    // Waydroid sizes its windows itself (persist.waydroid.width/height) and
    // re-plugs Android's display on every sized configure; a 0x0 one it
    // takes as "the compositor defers", so its windows only get those.
    bool sizesItself(const QWaylandXdgToplevel *toplevel) {
        const QString appId = toplevel->appId();
        return appId == QLatin1String("Waydroid") || appId.startsWith(QLatin1String("waydroid."));
    }

    // On screen: one of its views is shown, or drawn by a shown WindowTextureItem.
    bool surfaceShown(const QWaylandSurface *surface) {
        const QList<QWaylandView *> views = surface->views();
        return std::any_of(views.cbegin(), views.cend(), [](const QWaylandView *view) {
            const auto *item = qobject_cast<const QQuickItem *>(view->renderObject());
            return item && (WindowTextureItem::isShown(item) || WindowTextureItem::isSampled(item));
        });
    }

} // namespace

bool WaylandCompositor::showsSecureContent() const {
    const QList<MarathonSurfaceV1 *> all = m_marathonSurfaceManager->surfaces();
    if (std::any_of(all.cbegin(), all.cend(), [](const MarathonSurfaceV1 *marathon) {
            return marathon->secure() && surfaceShown(marathon->surface());
        }))
        return true;
    const QList<QWaylandSurface *> surfaces = QWaylandCompositor::surfaces();
    return std::any_of(surfaces.cbegin(), surfaces.cend(), [this](const QWaylandSurface *surface) {
        const auto *toplevel = surface->property("xdgToplevel").value<QWaylandXdgToplevel *>();
        return toplevel && m_secureApps.contains(toplevel->appId()) && surfaceShown(surface);
    });
}

void WaylandCompositor::setSecureApps(const QStringList &appIds) {
    m_secureApps = appIds;
}

// Runs on the render thread in beforeSynchronizing (GUI thread blocked), or
// on the GUI thread from the idle timer: never both at once.
void WaylandCompositor::sendPacedFrameCallbacks(bool idleTick) {
    const qint64 now  = m_frameClock.elapsed();
    bool         held = false;
    const QList<QWaylandSurface *> all = QWaylandCompositor::surfaces();
    for (QWaylandSurface *surface : all) {
        if (!surface->hasContent() || !surface->primaryView())
            continue;
        if (!m_enteredSurfaces.contains(surface)) {
            m_output->surfaceEnter(surface);
            m_enteredSurfaces.insert(surface);
        }
        const bool shown = !m_hiddenThrottle || surfaceShown(surface);
        if (idleTick && shown)
            continue;
        if (!m_frameThrottle.allow(surface, shown, now)) {
            held = true;
            continue;
        }
        if (idleTick)
            surface->frameStarted();
        surface->sendFrameCallbacks();
    }
    wl_display_flush_clients(display());
    if (held)
        QMetaObject::invokeMethod(
            this,
            [this]() {
                if (!m_hiddenFrameTimer.isActive())
                    m_hiddenFrameTimer.start();
            },
            Qt::QueuedConnection);
}

void WaylandCompositor::handleSurfaceCreated(QWaylandSurface *surface) {
    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Surface created:" << surface;

    connect(surface, &QObject::destroyed, this, [this, surface]() {
        m_enteredSurfaces.remove(surface);
        m_frameThrottle.forget(surface);
    });

    connect(surface, &QWaylandSurface::surfaceDestroyed, this,
            &WaylandCompositor::handleSurfaceDestroyed);
    connect(surface, &QWaylandSurface::inhibitsIdleChanged, this,
            &WaylandCompositor::checkIdleInhibitors);
    connect(surface, &QWaylandSurface::hasContentChanged, this,
            &WaylandCompositor::checkIdleInhibitors);

    // Client commit meter (harmless when the 1Hz stats timer isn't running).
    connect(surface, &QWaylandSurface::redraw, this,
            [this]() { m_clientCommitCount.fetchAndAddRelaxed(1); });

    if (m_presentFreeRun) {
        // Each client commit (redraw) refreshes the free-run credits and
        // schedules a frame, keeping the compositor at vsync while the app
        // animates. 4 frames (~64ms) of tail bridges brief commit gaps (fling
        // momentum ticks) without holding the loop awake once motion stops.
        connect(surface, &QWaylandSurface::redraw, this, [this]() {
            m_activeFrameCredits.storeRelaxed(4);
            if (m_window)
                m_window->update();
        });
    }

    connect(surface, &QObject::destroyed, this,
            [this, surface]() { m_textInputSurfaces.remove(surface); });

    int surfaceId           = m_nextSurfaceId++;
    m_surfaceMap[surfaceId] = surface;
    surface->setProperty("surfaceId", surfaceId);

    if (surface->client()) {
        qint64 pid = surface->client()->processId();
        if (pid > 0) {
            m_pidToSurfaceId[pid]       = surfaceId;
            m_surfaceIdToPid[surfaceId] = pid;
            qInfo() << "[WaylandCompositor] Linked PID" << pid << "to surface ID" << surfaceId;
        }
    }

    m_surfaces.append(surface);
    emit surfacesChanged();
}

void WaylandCompositor::activateSurface(int surfaceId) {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(getSurfaceById(surfaceId));
    const MarathonSurfaceV1 *marathon = m_marathonSurfaceManager->forSurface(surface);
    if (marathon && !marathon->focusable())
        return;
    if (surface && defaultSeat()) {
        // Android moves its focus only on wl_keyboard.enter: a raise re-enters
        // a window that kept the keyboard, once.
        const bool held = defaultSeat()->keyboardFocus() == surface;
        if (held && surface->property("foreignClient").toBool() &&
            m_keyboardFocusSince.isValid() && m_keyboardFocusSince.elapsed() > 1000)
            defaultSeat()->setKeyboardFocus(nullptr);
        defaultSeat()->setKeyboardFocus(surface);
        if (wlVerbose())
            qDebug() << "[WaylandCompositor] Activated surface (set keyboard focus):" << surfaceId;
    } else {
        qWarning() << "[WaylandCompositor] Failed to activate surface:" << surfaceId;
    }
}

void WaylandCompositor::releaseForeignKeyboard() {
    QWaylandSurface *focus = defaultSeat() ? defaultSeat()->keyboardFocus() : nullptr;
    if (focus && focus->property("foreignClient").toBool())
        defaultSeat()->setKeyboardFocus(nullptr);
}

// A minimized surface's views stop delivering wl_surface.frame callbacks,
// so a throttled client never commits again — and a restored view with no
// current buffer paints nothing, which never resumes the callbacks either.
// Firing the pending callbacks breaks that deadlock at restore.
void WaylandCompositor::setAppViewportSize(const QSize &size) {
    if (size == m_appViewportSize)
        return;
    m_appViewportSize = size;
    emit appViewportSizeChanged();
}

void WaylandCompositor::setCoverSize(const QSize &size) {
    if (size == m_coverSize)
        return;
    m_coverSize = size;
    qInfo() << "[WaylandCompositor] Covers configured to" << size;
    m_coverToplevels.removeAll(nullptr);
    for (const QPointer<QWaylandXdgToplevel> &toplevel : std::as_const(m_coverToplevels))
        configureCover(toplevel);
    emit coverSizeChanged();
}

void WaylandCompositor::configureCover(QWaylandXdgToplevel *toplevel) const {
    if (!toplevel)
        return;
    // Zero leaves the size to the app (keel/shell/PROTOCOL.md section 3).
    toplevel->sendConfigure(m_coverSize.isEmpty() ? QSize(0, 0) : m_coverSize,
                            QList<QWaylandXdgToplevel::State>());
}

QSize WaylandCompositor::appConfigureSize(QWaylandSurface *surface) const {
    const qreal scale = m_nativeClientScale->scaleFor(surface->client()->client());
    if (m_appViewportSize.width() > 0 && m_appViewportSize.height() > 0)
        return NativeClientScale::toLogical(m_appViewportSize, scale);
    return NativeClientScale::toLogical(
        (m_output && m_output->window()) ? m_output->window()->size() : QSize(), scale);
}

QVariantMap WaylandCompositor::marathonSurfaces() const {
    QVariantMap                      map;
    const QList<MarathonSurfaceV1 *> all = m_marathonSurfaceManager->surfaces();
    for (MarathonSurfaceV1 *marathon : all)
        map.insert(marathon->surface()->property("surfaceId").toString(),
                   QVariant::fromValue<QObject *>(marathon));
    return map;
}

qreal WaylandCompositor::nativeScale() const {
    return m_nativeClientScale->scale();
}

void WaylandCompositor::setNativeScale(qreal scale) {
    qInfo() << "[WaylandCompositor] Native client scale" << scale;
    m_nativeClientScale->setScale(scale);
}

bool WaylandCompositor::usesNativeScale(QWaylandSurface *surface) const {
    return surface && surface->client() &&
        !m_nativeClientScale->isFirstParty(surface->client()->client());
}

void WaylandCompositor::cancelTouch(QQuickItem *item) {
    // QWaylandQuickItem::touchUngrabEvent sends the cancel and stops the
    // client's points; their later moves stay with the shell.
    if (item)
        item->ungrabTouchPoints();
}

void WaylandCompositor::nudgeSurface(int surfaceId) {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(getSurfaceById(surfaceId));
    if (!surface)
        return;
    // Callbacks alone only unblock a client already waiting mid-frame; an
    // idle client needs a reason to redraw before a fresh view can take a
    // buffer. A same-state configure forces ack + commit, like restore does.
    surface->sendFrameCallbacks();
    // A client the shell did not launch is configured only on a change.
    if (surface->property("foreignClient").toBool())
        return;
    QWaylandXdgSurface *xdg = m_xdgSurfaceMap.value(surfaceId);
    if (!xdg || !xdg->toplevel() || sizesItself(xdg->toplevel()) ||
        ToplevelConfigure::repeat(xdg->toplevel()))
        return;
    QWaylandXdgToplevel *top  = xdg->toplevel();
    const QSize          size = surface->destinationSize();
    if (!size.isEmpty()) {
        // Mirror the toplevel's true state: dropping activated here
        // told every nudged app it was deactivated, demoting its RT
        // render priority and throttling it (felt like lost HW accel).
        QList<int> states{1};
        if (top->activated())
            states << 4;
        top->sendConfigure(size, states);
    }
}

void WaylandCompositor::resizeToplevel(QWaylandXdgToplevel *toplevel, const QSize &size) {
    if (toplevel)
        ToplevelConfigure::resize(toplevel, sizesItself(toplevel) ? QSize(0, 0) : size);
}

bool WaylandCompositor::recentUserInput(int ms) const {
    return m_lastUserInput.isValid() && m_lastUserInput.elapsed() < ms;
}

bool WaylandCompositor::configureSettled(int surfaceId) const {
    QWaylandXdgSurface *xdg = m_xdgSurfaceMap.value(surfaceId);
    return !xdg || !xdg->toplevel() || ToplevelConfigure::settled(xdg->toplevel());
}

// QWaylandInputMethodControl can't drive the keyboard: it subscribes only to
// text-input objects that exist when the surface is created, and Qt creates
// them lazily on a client's first request, so for most surfaces it never sees
// a client enable or disable text input. Subscribe to the per-seat text-input
// objects directly instead. Neither class exports its meta-object, so they are
// found by class name and connected through MOC's string dispatch.
void WaylandCompositor::connectTextInputs() {
    QWaylandSeat *seat = defaultSeat();
    if (!seat)
        return;
    const auto extensions = seat->extensions();
    for (QWaylandCompositorExtension *ext : extensions) {
        const QByteArray cls = ext->metaObject()->className();
        if (cls != "QWaylandTextInput" && cls != "QWaylandTextInputV3")
            continue;
        connect(ext, SIGNAL(surfaceEnabled(QWaylandSurface *)), this,
                SLOT(handleTextInputSurfaceEnabled(QWaylandSurface *)), Qt::UniqueConnection);
        connect(ext, SIGNAL(surfaceDisabled(QWaylandSurface *)), this,
                SLOT(handleTextInputSurfaceDisabled(QWaylandSurface *)), Qt::UniqueConnection);
        connect(ext, SIGNAL(updateInputMethod(Qt::InputMethodQueries)), this,
                SLOT(handleTextInputUpdate(Qt::InputMethodQueries)), Qt::UniqueConnection);
    }
}

namespace {
    struct ClientCreatedWatch {
        wl_listener        listener;
        WaylandCompositor *compositor;
    };

    struct TextInputBindWatch {
        wl_listener        resourceCreated;
        wl_listener        clientDestroyed;
        WaylandCompositor *compositor;
    };

    void textInputResourceCreated(wl_listener *listener, void *data) {
        TextInputBindWatch *watch    = wl_container_of(listener, watch, resourceCreated);
        auto               *resource = static_cast<wl_resource *>(data);
        const char         *cls      = wl_resource_get_class(resource);
        if (std::strcmp(cls, "zwp_text_input_v3") != 0 &&
            std::strcmp(cls, "zwp_text_input_v2") != 0)
            return;
        // Queued: Qt records the client as a text-input user only after the
        // resource is set up, and takeFocus() checks that record.
        WaylandCompositor *compositor = watch->compositor;
        wl_client         *client     = wl_resource_get_client(resource);
        QMetaObject::invokeMethod(
            compositor, [compositor, client]() { compositor->handleTextInputBound(client); },
            Qt::QueuedConnection);
    }

    void textInputClientDestroyed(wl_listener *listener, void *) {
        TextInputBindWatch *watch = wl_container_of(listener, watch, clientDestroyed);
        wl_list_remove(&watch->resourceCreated.link);
        wl_list_remove(&watch->clientDestroyed.link);
        delete watch;
    }

    void clientCreated(wl_listener *listener, void *data) {
        ClientCreatedWatch *created   = wl_container_of(listener, created, listener);
        auto               *client    = static_cast<wl_client *>(data);
        auto               *watch     = new TextInputBindWatch{};
        watch->compositor             = created->compositor;
        watch->resourceCreated.notify = textInputResourceCreated;
        watch->clientDestroyed.notify = textInputClientDestroyed;
        wl_client_add_resource_created_listener(client, &watch->resourceCreated);
        wl_client_add_destroy_listener(client, &watch->clientDestroyed);
    }
} // namespace

// Qt sends a text-input enter only from QWaylandQuickItem::takeFocus(), and
// only to clients that already hold a text-input object. GTK creates its
// object when a field first takes focus, which is after the tap that took
// focus, so it never gets the enter and never enables text input. Watch
// every client for text-input objects and take focus again when one appears.
void WaylandCompositor::watchTextInputBinds() {
    static ClientCreatedWatch watch;
    watch.compositor      = this;
    watch.listener.notify = clientCreated;
    wl_display_add_client_created_listener(static_cast<wl_display *>(display()), &watch.listener);
}

void WaylandCompositor::handleTextInputBound(wl_client *client) {
    // The seat's text-input objects are created by the first client to bind.
    connectTextInputs();
    QWaylandSurface *focus = defaultSeat() ? defaultSeat()->keyboardFocus() : nullptr;
    if (!focus || focus->waylandClient() != client || !focus->primaryView())
        return;
    if (auto *item = qobject_cast<QWaylandQuickItem *>(focus->primaryView()->renderObject()))
        item->takeFocus();
}

void WaylandCompositor::handleTextInputSurfaceEnabled(QWaylandSurface *surface) {
    m_textInputSurfaces.insert(surface);
    if (defaultSeat() && surface == defaultSeat()->keyboardFocus())
        emit nativeTextInputPanelRequested(true);
}

void WaylandCompositor::handleTextInputUpdate(Qt::InputMethodQueries queries) {
    if (queries & Qt::ImHints)
        emit textInputHintsChanged();
}

void WaylandCompositor::handleTextInputSurfaceDisabled(QWaylandSurface *surface) {
    m_textInputSurfaces.remove(surface);
    if (defaultSeat() && surface == defaultSeat()->keyboardFocus())
        emit nativeTextInputPanelRequested(false);
}

void WaylandCompositor::handleXdgToplevelCreated(QWaylandXdgToplevel *toplevel,
                                                 QWaylandXdgSurface  *xdgSurface) {
    if (!toplevel || !xdgSurface) {
        qWarning()
            << "[WaylandCompositor] XDG toplevel creation with null toplevel/xdgSurface - ignoring";
        return;
    }

    if (!m_output) {
        qWarning() << "[WaylandCompositor] No output available for XDG toplevel - ignoring surface";
        return;
    }

    QWaylandSurface *surface = xdgSurface->surface();
    if (!surface || !surface->client()) {
        qWarning()
            << "[WaylandCompositor] XDG surface has no valid Wayland surface or client - ignoring";
        return;
    }

    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));
    surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
    surface->setProperty("title", toplevel->title());
    surface->setProperty("appId", toplevel->appId());

    int surfaceId              = surface->property("surfaceId").toInt();
    m_xdgSurfaceMap[surfaceId] = xdgSurface;

    qInfo() << "[WaylandCompositor] New toplevel:" << surfaceId << toplevel->appId() << "-"
            << toplevel->title();

    // A Keel app's cover is a second top-level window of the same client,
    // known only by its title, which arrives after the toplevel is created;
    // by the client's first commit it is set.
    {
        // A Keel app's cover is a top-level window known only by its title,
        // which arrives just after the toplevel; Keel may create it before
        // the app's main window.
        QPointer<QWaylandXdgToplevel> pendingToplevel(toplevel);
        QPointer<QWaylandXdgSurface>  pendingXdg(xdgSurface);
        auto                          decided = std::make_shared<bool>(false);
        // Decide once: on the title (sent before the first commit), the first
        // commit, or after a short wait for a client that sets neither.
        auto decide = [this, decided, pendingToplevel, pendingXdg](bool final) {
            if (*decided || !pendingToplevel || !pendingXdg)
                return;
            const bool cover  = KeelCover::isCoverTitle(pendingToplevel->title());
            const bool dialog = KeelDialog::isDialogTitle(pendingToplevel->title());
            if (!cover && !dialog && !final)
                return;
            *decided = true;
            if (cover)
                adoptCover(pendingToplevel, pendingXdg);
            else if (dialog)
                mapDialog(pendingToplevel, pendingXdg);
            else
                mapToplevel(pendingToplevel, pendingXdg);
        };
        connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [decide]() { decide(false); });
        connect(surface, &QWaylandSurface::redraw, this, [decide]() { decide(true); });
        QTimer::singleShot(300, this, [decide]() { decide(true); });
    }
}

void WaylandCompositor::mapToplevel(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface) {
    QWaylandSurface *surface   = xdgSurface->surface();
    const int        surfaceId = surface->property("surfaceId").toInt();

    // Send an initial xdg_toplevel.configure as soon as the toplevel is created
    // so the client can ack + commit its first content buffer. The QML side
    // (WaylandShellSurfaceItem.sendSizeToApp) only fires after the surface item
    // gets a non-zero size, which depends on layout/loader timing -- the
    // surface can sit unconfigured for arbitrarily long, and Qt's qtwayland
    // client decides "window inexposed" and stops painting. By sending the
    // output size up-front, the client always gets a first configure within
    // milliseconds of mapping and can proceed to attach + commit its buffer.
    // The shell files the window first: it is activated only if it will be
    // shown, so its one sized configure is final.
    emit surfaceCreated(surface, surfaceId, xdgSurface);
    {
        MarathonSurfaceV1 *marathon = m_marathonSurfaceManager->forSurface(surface);
        if (marathon)
            marathon->sendInsets(QMargins(), 0);
        const bool  ownSize     = sizesItself(toplevel);
        const QSize initialSize = ownSize ? QSize(0, 0) : appConfigureSize(surface);
        if (ownSize || (initialSize.width() > 0 && initialSize.height() > 0)) {
            QList<QWaylandXdgToplevel::State> states{QWaylandXdgToplevel::MaximizedState};
            if ((!marathon || marathon->focusable()) &&
                !surface->property("mappedInBackground").toBool())
                states << QWaylandXdgToplevel::ActivatedState;
            ToplevelConfigure::send(toplevel, initialSize, states);
            qInfo() << "[WaylandCompositor] Sent initial configure" << initialSize << states
                    << "for surfaceId" << surfaceId;
        }
    }
    surface->setProperty("toplevelMapped", true);
    const QVariant pendingActivation = surface->property("pendingActivationPid");
    if (pendingActivation.isValid())
        emit surfaceActivated(surface, surfaceId, xdgSurface, pendingActivation.toLongLong());

    // The shell-surface item answers these with the output size in its own
    // units; a native-scale client is put back at its app-area size.
    if (usesNativeScale(surface)) {
        const auto resize = [this, surfaceId]() { nudgeSurface(surfaceId); };
        connect(toplevel, &QWaylandXdgToplevel::setMaximized, this, resize, Qt::QueuedConnection);
        connect(toplevel, &QWaylandXdgToplevel::unsetMaximized, this, resize, Qt::QueuedConnection);
        connect(toplevel, &QWaylandXdgToplevel::setFullscreen, this, resize, Qt::QueuedConnection);
        connect(toplevel, &QWaylandXdgToplevel::unsetFullscreen, this, resize,
                Qt::QueuedConnection);
    }

    QPointer<QWaylandXdgToplevel> safeToplevel(toplevel);
    QPointer<QWaylandSurface>     safeSurface(surface);

    connect(toplevel, &QWaylandXdgToplevel::titleChanged, this,
            [this, safeToplevel, safeSurface]() {
                if (safeToplevel && safeSurface) {
                    safeSurface->setProperty("title", safeToplevel->title());
                }
            });

    connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this,
            [this, safeToplevel, safeSurface]() {
                if (safeToplevel && safeSurface) {
                    safeSurface->setProperty("appId", safeToplevel->appId());
                }
            });

    const bool treatUnmapAsClose = envBool("MARATHON_TREAT_UNMAP_AS_CLOSE", false);
    if (treatUnmapAsClose) {
        connect(
            surface, &QWaylandSurface::hasContentChanged, this, [this, safeSurface, surfaceId]() {
                if (safeSurface && !safeSurface->hasContent()) {
                    qInfo() << "[WaylandCompositor] Surface lost content (window hidden/unmapped) "
                               "- surfaceId:"
                            << surfaceId;
                    qInfo() << "[WaylandCompositor] Treating as app close (legacy mode)";

                    emit surfaceDestroyed(safeSurface.data(), surfaceId);

                    if (m_surfaceIdToPid.contains(surfaceId)) {
                        qint64 pid = m_surfaceIdToPid[surfaceId];
                        m_pidToSurfaceId.remove(pid);
                        m_surfaceIdToPid.remove(surfaceId);
                        qDebug() << "[WaylandCompositor] Cleaned up PID mapping for" << pid;
                    }

                    m_surfaceMap.remove(surfaceId);
                    m_xdgSurfaceMap.remove(surfaceId);
                    m_surfaces.removeAll(safeSurface);
                    emit surfacesChanged();
                }
            });
    }
}

void WaylandCompositor::mapDialog(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface) {
    QWaylandSurface *surface = xdgSurface->surface();
    surface->setProperty("isDialog", true);
    toplevel->sendConfigure(appConfigureSize(surface),
                            QList<QWaylandXdgToplevel::State>{QWaylandXdgToplevel::ActivatedState,
                                                              QWaylandXdgToplevel::MaximizedState});
    emit dialogCreated(surface, surface->property("surfaceId").toInt(), xdgSurface);
}

void WaylandCompositor::adoptCover(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface) {
    QWaylandSurface *surface = xdgSurface->surface();
    surface->setProperty("isCover", true);
    m_coverToplevels.removeAll(nullptr);
    m_coverToplevels.append(toplevel);
    configureCover(toplevel);
    QPointer<QWaylandSurface>     safeSurface(surface);
    QPointer<QWaylandXdgToplevel> safeToplevel(toplevel);
    // The app id can follow the title, so the cover is filed under it when it comes.
    auto file = [this, safeSurface, safeToplevel]() {
        if (!safeSurface || !safeToplevel || safeToplevel->appId().isEmpty())
            return;
        const QString appId = safeToplevel->appId();
        m_covers.insert(appId, safeSurface);
        qInfo() << "[WaylandCompositor] Cover for" << appId;
        emit coverChanged(appId);
    };
    connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, file);
    // The surface is still alive while surfaceDestroyed is emitted.
    connect(surface, &QWaylandSurface::surfaceDestroyed, this, [this]() {
        QTimer::singleShot(0, this, [this]() {
            for (auto it = m_covers.begin(); it != m_covers.end();) {
                if (!it.value()) {
                    const QString appId = it.key();
                    it                  = m_covers.erase(it);
                    emit coverChanged(appId);
                } else {
                    ++it;
                }
            }
        });
    });
    file();
}

// An activation that arrives before the toplevel maps is held until it does.
void WaylandCompositor::handleActivation(QWaylandSurface *surface, QObject *launch) {
    const auto  *process   = qobject_cast<const QProcess *>(launch);
    const qint64 launchPid = process && process->processId() > 0 ? process->processId() : -1;
    if (!surface->property("toplevelMapped").toBool()) {
        surface->setProperty("pendingActivationPid", launchPid);
        return;
    }
    emit surfaceActivated(surface, surface->property("surfaceId").toInt(),
                          surface->property("xdgSurface").value<QWaylandXdgSurface *>(), launchPid);
}

QWaylandSurface *WaylandCompositor::coverSurface(const QString &appId) const {
    return m_covers.value(appId).data();
}

void WaylandCompositor::handleXdgPopupCreated(QWaylandXdgPopup   *popup,
                                              QWaylandXdgSurface *xdgSurface) {

    if (!popup || !xdgSurface) {
        qWarning() << "[WaylandCompositor] XDG popup creation with null objects - ignoring";
        return;
    }

    QWaylandSurface *surface = xdgSurface->surface();
    if (!surface) {
        qWarning() << "[WaylandCompositor] XDG popup has no surface - ignoring";
        return;
    }

    int surfaceId = surface->property("surfaceId").toInt();
    if (surfaceId == 0) {
        surfaceId               = m_nextSurfaceId++;
        m_surfaceMap[surfaceId] = surface;
        surface->setProperty("surfaceId", surfaceId);
    }

    if (qEnvironmentVariableIsSet("MARATHON_DEBUG")) {
        QWaylandXdgSurface *parentXdgSurface = popup->parentXdgSurface();
        qWarning() << "[WaylandCompositor] Popup created:" << surfaceId << "parent:"
                   << (parentXdgSurface && parentXdgSurface->surface() ?
                           parentXdgSurface->surface()->property("surfaceId").toInt() :
                           -1);
    }

    surface->setProperty("isPopup", true);
    surface->setProperty("xdgPopup", QVariant::fromValue(popup));
    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));

    m_surfaces.append(surface);
    m_xdgSurfaceMap[surfaceId] = xdgSurface;
    emit surfacesChanged();
}

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface) {
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();

    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        Q_UNUSED(surface->property("surfaceId").toInt());
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());

        QPointer<QWaylandWlShellSurface> safeWlShell(wlShellSurface);
        QPointer<QWaylandSurface>        safeSurface(surface);
        connect(wlShellSurface, &QWaylandWlShellSurface::titleChanged, this,
                [this, safeWlShell, safeSurface]() {
                    if (safeWlShell && safeSurface) {
                        safeSurface->setProperty("title", safeWlShell->title());
                    }
                });
    }
}

void WaylandCompositor::handleSurfaceDestroyed() {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(sender());
    if (!surface)
        return;

    int surfaceId = surface->property("surfaceId").toInt();
    qDebug() << "[WaylandCompositor] Surface destroyed, ID:" << surfaceId;

    if (m_surfaceIdToPid.contains(surfaceId)) {
        qint64 pid = m_surfaceIdToPid[surfaceId];
        m_pidToSurfaceId.remove(pid);
        m_surfaceIdToPid.remove(surfaceId);
        qDebug() << "[WaylandCompositor] Cleaned up PID mapping for" << pid;
    }

    m_surfaceMap.remove(surfaceId);
    m_xdgSurfaceMap.remove(surfaceId);
    m_surfaces.removeAll(surface);
    checkIdleInhibitors();

    emit surfacesChanged();
    emit surfaceDestroyed(surface, surfaceId);
}

void WaylandCompositor::handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (!process)
        return;

    QString       command       = m_processes.value(process, "unknown");
    qint64        pid           = process->processId();
    const bool    alreadyClosed = process->property("marathonAppClosedEmitted").toBool();

    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty()) {
        if (QFile::exists(desktopFile)) {
            if (!QFile::remove(desktopFile)) {
                qWarning() << "[WaylandCompositor] Failed to remove temp desktop file:"
                           << desktopFile;
            }
        }
    }

    bool       isGApplication = command.contains("gapplication launch");
    const bool closeRequested = process->property("marathonCloseRequested").toBool();

    if (isGApplication) {
        qInfo() << "[WaylandCompositor] gapplication process finished:" << command
                << "exitCode:" << exitCode << "(surface tracking active, not PID-based)";
    } else {
        const QString statusStr =
            (exitStatus == QProcess::NormalExit ? "normal" :
                                                  (closeRequested ? "terminated" : "crashed"));
        qInfo() << "[WaylandCompositor] Process finished:" << command << "PID:" << pid
                << "exitCode:" << exitCode << "status:" << statusStr;

        const bool abnormal = (exitStatus != QProcess::NormalExit) || (exitCode != 0);
        if (abnormal && !closeRequested) {
            const QString outputTail = process->property("marathonStdoutTail").toString();
            const QString errTail    = process->property("marathonStderrTail").toString();
            const QString output =
                outputTail + QString::fromLocal8Bit(process->readAllStandardOutput());
            const QString err = errTail + QString::fromLocal8Bit(process->readAllStandardError());
            if (!output.trimmed().isEmpty())
                qWarning() << "[WaylandCompositor] stdout tail for" << command << ":\n"
                           << output.trimmed();
            if (!err.trimmed().isEmpty())
                qWarning() << "[WaylandCompositor] stderr tail for" << command << ":\n"
                           << err.trimmed();
        }

        if (pid > 0 && !alreadyClosed) {
            emit appClosed(pid);
        }
    }

    if (pid > 0 && m_pidToSurfaceId.contains(pid)) {
        int surfaceId = m_pidToSurfaceId[pid];
        qInfo() << "[WaylandCompositor] Closing surface for PID" << pid
                << "surfaceId:" << surfaceId;

        if (m_surfaceMap.contains(surfaceId)) {
            QWaylandSurface *surface = m_surfaceMap[surfaceId];
            if (surface && surface->client()) {
                surface->client()->close();
            }
        }
    }

    m_processes.remove(process);
    process->deleteLater();
}

void WaylandCompositor::calculateAndSetPhysicalSize() {
    if (!m_window || !m_output) {
        qWarning() << "[WaylandCompositor] Cannot configure output metrics - missing window/output";
        return;
    }

    QScreen *screen = m_window->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();

    qreal dpr = 1.0;
    if (screen)
        dpr = screen->devicePixelRatio();

    const int scale = qMax(1, qRound(dpr));
    if (m_output->scaleFactor() != scale)
        m_output->setScaleFactor(scale);

    const QSize windowSize = m_window->size();
    m_output->setAvailableGeometry(QRect(QPoint(0, 0), windowSize));

    QSize       physicalSizeMm(0, 0);
    const qreal panelDpi = DeviceProfile::instance().panelDpi();
    if (panelDpi > 0.0) {
        physicalSizeMm = QSize(qMax(1, qRound(windowSize.width() / panelDpi * 25.4)),
                               qMax(1, qRound(windowSize.height() / panelDpi * 25.4)));
    } else if (screen) {
        const QSizeF hostMm = screen->physicalSize();
        const QSize  hostPx = screen->geometry().size();

        if (hostMm.isValid() && hostMm.width() > 0.0 && hostMm.height() > 0.0 && hostPx.isValid() &&
            hostPx.width() > 0 && hostPx.height() > 0) {
            const qreal rx =
                static_cast<qreal>(windowSize.width()) / static_cast<qreal>(hostPx.width());
            const qreal ry =
                static_cast<qreal>(windowSize.height()) / static_cast<qreal>(hostPx.height());
            physicalSizeMm =
                QSize(qMax(1, qRound(hostMm.width() * rx)), qMax(1, qRound(hostMm.height() * ry)));
        }
    }

    if (!physicalSizeMm.isValid() || physicalSizeMm.width() <= 0 || physicalSizeMm.height() <= 0) {
        const qreal mmPerInch = 25.4;
        qreal       dpi       = 0.0;
        if (screen) {
            dpi = screen->physicalDotsPerInch();
            if (dpi <= 0.0)
                dpi = screen->logicalDotsPerInch();
        }
        if (dpi <= 0.0)
            dpi = 96.0;

        physicalSizeMm = QSize(qMax(1, qRound((windowSize.width() / dpi) * mmPerInch)),
                               qMax(1, qRound((windowSize.height() / dpi) * mmPerInch)));
    }

    m_output->setPhysicalSize(physicalSizeMm);

    qInfo() << "[WaylandCompositor] Output metrics:"
            << "window=" << windowSize << "scale=" << m_output->scaleFactor()
            << "physical(mm)=" << physicalSizeMm << "screenDpr=" << dpr;
}

void WaylandCompositor::setCompositorRealtimePriority() {
#ifdef Q_OS_LINUX
    // Elevate the QSGRenderThread (NOT the main thread that runs this
    // constructor). beforeSynchronizing fires on the render thread, so a
    // DirectConnection lambda runs in the right context for setsched.
    if (!m_window)
        return;
    connect(
        m_window, &QQuickWindow::beforeSynchronizing, this,
        []() {
            static bool primed = false;
            if (primed)
                return;
            primed = true;
            if (const int rc = marathon::rt::setCurrentThreadPriority(1); rc != 0)
                qWarning() << "[WaylandCompositor] QSGRenderThread RT elevation failed:"
                           << strerror(rc);
        },
        Qt::DirectConnection);
#endif
}

void WaylandCompositor::handleProcessError(QProcess::ProcessError error) {
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (!process)
        return;

    QString    command        = m_processes.value(process, "unknown");
    const bool closeRequested = process->property("marathonCloseRequested").toBool();
    QString    errorString;

    switch (error) {
        case QProcess::FailedToStart:
            errorString = "Failed to start (executable not found or insufficient permissions)";
            break;
        case QProcess::Crashed: errorString = "Crashed"; break;
        case QProcess::Timedout: errorString = "Timed out"; break;
        case QProcess::WriteError: errorString = "Write error"; break;
        case QProcess::ReadError: errorString = "Read error"; break;
        default: errorString = "Unknown error"; break;
    }

    if (error == QProcess::Crashed && closeRequested) {
        qInfo() << "[WaylandCompositor] Process exited after close request for" << command;
        return;
    }

    qWarning() << "[WaylandCompositor] Process error for" << command << ":" << errorString;
    qWarning() << "[WaylandCompositor] Error details:" << process->errorString();

    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty() && QFile::exists(desktopFile)) {
        QFile::remove(desktopFile);
    }

    const QString outputTail = process->property("marathonStdoutTail").toString();
    const QString errTail    = process->property("marathonStderrTail").toString();
    const QString output = outputTail + QString::fromLocal8Bit(process->readAllStandardOutput());
    const QString err    = errTail + QString::fromLocal8Bit(process->readAllStandardError());

    if (!output.trimmed().isEmpty())
        qWarning() << "[WaylandCompositor] stdout tail for" << command << ":\n" << output.trimmed();
    if (!err.trimmed().isEmpty())
        qWarning() << "[WaylandCompositor] stderr tail for" << command << ":\n" << err.trimmed();

    if (error == QProcess::Crashed) {
        const qint64 pid = process->processId();
        if (pid > 0 && !process->property("marathonAppClosedEmitted").toBool()) {
            process->setProperty("marathonAppClosedEmitted", true);
            emit appClosed(pid);
        }
    }

    if (error == QProcess::FailedToStart) {
        m_processes.remove(process);
        process->deleteLater();
    }
}

void WaylandCompositor::setCompositorActive(bool active) {
    if (!m_window)
        return;

    if (active) {
        // Always re-assert display power on wake, even if the window already
        // reports visible. Window-visibility is NOT a reliable proxy for CRTC
        // power: a raced double-toggle or a partial wake can leave the window
        // visible while the CRTC sits at ACTIVE=0 -- and the old
        // `active == isVisible()` early-return then skipped the CRTC re-enable
        // outright, leaving the panel dark with no recovery (an unwakeable
        // screen). setDisplayPowerState is idempotent, so re-asserting a live
        // CRTC is a cheap no-op. Power the pipeline on BEFORE resuming page
        // flips so the first flip lands on a live CRTC (a sleeping one wedges
        // eglfs_kms with EINVAL).
        setDisplayPowerState(true);
        if (!m_window->isVisible()) {
            qDebug() << "[WaylandCompositor] Resuming compositor window";
            m_window->setVisible(true);
        }
        return;
    }

    // Suspending. Idempotent: if the window is already hidden we are already
    // suspended, nothing to do.
    if (!m_window->isVisible())
        return;
    qDebug() << "[WaylandCompositor] Suspending compositor window";

    // Hide first, then ask the scene graph to release its GL
    // resources. Without this, the render thread keeps trying to flip into
    // a soon-to-be DPMS-off CRTC and eglfs_kms wedges with EINVAL on
    // virtio-gpu (the page-flip cannot land on a sleeping connector).
    m_window->setVisible(false);
    m_window->releaseResources();

    // Now that page flips are halted, power the CRTC/panel down. Turning
    // off only the backlight LED (DisplayManagerCpp) leaves the DCSS
    // display controller scanning out 720x1440@63Hz to a still-powered
    // DSI panel — measured at ~3W in Doze, because continuous scanout
    // pins the memory-controller + interconnect devfreq at 800MHz (floor
    // is 169MHz) and the mxsfb-dsi panel regulators (avdd/avee) never
    // gate. A real DPMS-off stops scanout, drops the memory bus, and
    // powers the panel rails down — the single biggest standby win.
    setDisplayPowerState(false);
}

// Cache the DRM master fd + CRTC id + ACTIVE property id from Qt's
// eglfs_kms integration. Returns true if we have everything needed to
// drive the CRTC's ACTIVE property ourselves. Idempotent.
//
// We take Qt's OWN master fd (via QPlatformNativeInterface "dri_fd")
// rather than open()ing /dev/dri/card* ourselves — only the DRM master
// may issue a modeset, and Qt eglfs holds mastership on the card. A
// second open() would be a non-master fd and every atomic commit would
// return EACCES.
bool WaylandCompositor::initAtomicDisplay() {
    if (m_atomicDisplayReady)
        return true;
    if (m_atomicDisplayFailed)
        return false;

    QPlatformNativeInterface *ni = QGuiApplication::platformNativeInterface();
    if (!ni || !m_window) {
        m_atomicDisplayFailed = true;
        return false;
    }
    QScreen *screen = m_window->screen();
    if (!screen) {
        m_atomicDisplayFailed = true;
        return false;
    }

    void *fdPtr   = ni->nativeResourceForIntegration(QByteArrayLiteral("dri_fd"));
    void *crtcPtr = ni->nativeResourceForScreen(QByteArrayLiteral("dri_crtcid"), screen);
    m_driFd       = fdPtr ? static_cast<int>(reinterpret_cast<qintptr>(fdPtr)) : -1;
    m_crtcId      = crtcPtr ? static_cast<uint32_t>(reinterpret_cast<qintptr>(crtcPtr)) : 0;

    if (m_driFd < 0 || m_crtcId == 0) {
        qWarning() << "[WaylandCompositor] atomic display init: no dri_fd/crtcid from eglfs"
                   << "(fd" << m_driFd << "crtc" << m_crtcId << ") — DPMS disabled";
        m_atomicDisplayFailed = true;
        return false;
    }

    // Enable atomic on this fd (harmless if eglfs_kms_atomic already did).
    drmSetClientCap(m_driFd, DRM_CLIENT_CAP_ATOMIC, 1);

    // Resolve the CRTC's "ACTIVE" property id.
    drmModeObjectProperties *props =
        drmModeObjectGetProperties(m_driFd, m_crtcId, DRM_MODE_OBJECT_CRTC);
    if (!props) {
        qWarning() << "[WaylandCompositor] atomic display init: cannot read CRTC props";
        m_atomicDisplayFailed = true;
        return false;
    }
    for (uint32_t i = 0; i < props->count_props; ++i) {
        drmModePropertyRes *p = drmModeGetProperty(m_driFd, props->props[i]);
        if (!p)
            continue;
        if (qstrcmp(p->name, "ACTIVE") == 0)
            m_crtcActivePropId = props->props[i];
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(props);

    if (m_crtcActivePropId == 0) {
        qWarning() << "[WaylandCompositor] atomic display init: no ACTIVE prop on CRTC";
        m_atomicDisplayFailed = true;
        return false;
    }

    qInfo() << "[WaylandCompositor] atomic display ready: fd" << m_driFd << "crtc" << m_crtcId
            << "ACTIVE prop" << m_crtcActivePropId;
    m_atomicDisplayReady = true;
    return true;
}

// DPMS transition for the primary output via a DIRECT libdrm atomic
// commit of the CRTC's ACTIVE property. Gated behind MARATHON_DOZE_DPMS
// (default off).
//
// Why not Qt's QPlatformScreen::setPowerState: on i.MX8MQ + mxsfb + nwl
// DSI, a full CRTC teardown (zeroing MODE_ID + CRTC_ID) fails atomic
// validation because a plane+framebuffer is still bound to a now-
// modeless CRTC — the panel wedges dark and only a reboot recovers.
// This is swaywm/wlroots#1889, filed on this exact hardware. The clean
// path Phosh/wlroots uses — and what we replicate here — is to toggle
// ONLY the CRTC ACTIVE property, leaving MODE_ID intact.
//
// VALIDATED on-device 2026-07-01 (instrumented): ACTIVE=0/1 commits
// return 0, readback confirms the value sticks, wake is clean across
// many cycles (NO wedge — unlike Qt's setPowerState), and the panel's
// AVDD rail gates on ACTIVE=0. This is the correct, shippable display-
// off for the DSI panel.
//
// HOWEVER it does NOT unlock the DDR self-refresh win we hoped for:
// with the CRTC confirmed disabled, the memory-controller stays pinned
// at 800MHz. A dev_pm_qos MIN_FREQUENCY=166.9MHz floor (held by a NON-
// display consumer — it survives CRTC disable) excludes the usable
// 25/100MHz DDR OPPs. Dropping the DDR to self-refresh is therefore a
// kernel/DTB task (find + release that QoS holder), independent of this
// compositor change. See the "standby power floor" / "doze dpms" notes.
//
// Render must already be paused (setVisible(false)+releaseResources)
// before ACTIVE=0, and restored to ACTIVE=1 before render resumes —
// callers in setCompositorActive guarantee that ordering.
void WaylandCompositor::setDisplayPowerState(bool on) {
    // DEFAULT ON as of 2026-07-01. Validated: the atomic CRTC ACTIVE=0
    // display-off drops Doze draw from ~2.8W to ~0.1W (measured; matches
    // the i.MX8MQ ~105mW deep-idle floor), and the wake path re-lights
    // the panel reliably — 15/15 physical doze/wake cycles incl. 30s
    // deep-idle holds, after the backlight-after-CRTC ordering fix in
    // DisplayManagerCpp::setScreenState + forceBacklightOn(). Set
    // MARATHON_DOZE_DPMS=0 to disable (e.g. bring-up on other panels).
    static const bool enabled = DeviceProfile::instance().dozeDpms();
    if (!enabled)
        return;
    if (!initAtomicDisplay())
        return;

    drmModeAtomicReq *req = drmModeAtomicAlloc();
    if (!req)
        return;
    drmModeAtomicAddProperty(req, m_crtcId, m_crtcActivePropId, on ? 1 : 0);

    // ALLOW_MODESET: toggling ACTIVE is a modeset-class change. No page
    // flip event requested (nullptr user_data) — this is a blocking
    // synchronous commit, appropriate for a screen on/off transition.
    const int ret = drmModeAtomicCommit(m_driFd, req, DRM_MODE_ATOMIC_ALLOW_MODESET, nullptr);
    drmModeAtomicFree(req);

    if (ret != 0) {
        qWarning() << "[WaylandCompositor] CRTC ACTIVE=" << on << "atomic commit failed:" << ret
                   << strerror(-ret);
        return;
    }
    qInfo() << "[WaylandCompositor] display" << (on ? "ON" : "OFF")
            << "via CRTC ACTIVE atomic commit";
}

void WaylandCompositor::setOutputOrientation(const QString &orientation) {
    if (!m_output || !m_window) {
        qWarning() << "[WaylandCompositor] Cannot set output orientation: missing output or window";
        return;
    }

    QWaylandOutput::Transform transform      = QWaylandOutput::TransformNormal;
    qreal                     rotation       = 0.0;
    bool                      swapDimensions = false;

    if (orientation == "portrait") {
        transform      = QWaylandOutput::TransformNormal;
        rotation       = 0.0;
        swapDimensions = false;
    } else if (orientation == "landscape") {
        transform      = QWaylandOutput::Transform90;
        rotation       = 90.0;
        swapDimensions = true;
    } else if (orientation == "portrait-inverted") {
        transform      = QWaylandOutput::Transform180;
        rotation       = 180.0;
        swapDimensions = false;
    } else if (orientation == "landscape-inverted") {
        transform      = QWaylandOutput::Transform270;
        rotation       = 270.0;
        swapDimensions = true;
    } else {
        qWarning() << "[WaylandCompositor] Invalid rotation request:" << orientation;
        return;
    }

    qInfo() << "[WaylandCompositor] Applying rotation:" << orientation << "(" << rotation
            << "degrees, Transform =" << transform << ")";

    QQuickItem *contentItem = m_window->contentItem();
    if (contentItem) {
        qreal W = m_window->width();
        qreal H = m_window->height();

        contentItem->setTransformOrigin(QQuickItem::TopLeft);
        contentItem->setRotation(rotation);

        if (swapDimensions) {
            contentItem->setWidth(H);
            contentItem->setHeight(W);
        } else {
            contentItem->setWidth(W);
            contentItem->setHeight(H);
        }

        switch (static_cast<int>(rotation)) {
            case 0:
                contentItem->setX(0);
                contentItem->setY(0);
                break;

            case 90:
                contentItem->setX(W);
                contentItem->setY(0);
                break;

            case 180:
                contentItem->setX(W);
                contentItem->setY(H);
                break;

            case 270:
                contentItem->setX(0);
                contentItem->setY(H);
                break;

            default:
                qWarning() << "[WaylandCompositor] Unexpected rotation angle:" << rotation
                           << "(expected 0/90/180/270); leaving content position unchanged";
                break;
        }
    } else {
        qWarning() << "[WaylandCompositor] No content item to rotate";
    }

    m_output->setTransform(transform);
    calculateAndSetPhysicalSize();
}

void WaylandCompositor::injectKey(int key, int modifiers, bool pressed) {
    if (!defaultSeat()) {
        qWarning() << "[WaylandCompositor] No default seat found for key injection";
        return;
    }

    QEvent::Type type = pressed ? QEvent::KeyPress : QEvent::KeyRelease;
    QKeyEvent    event(type, key, static_cast<Qt::KeyboardModifiers>(modifiers));
    defaultSeat()->sendFullKeyEvent(&event);
    qInfo() << "[WaylandCompositor] Injected Key:" << key << "Modifiers:" << modifiers
            << "Pressed:" << pressed;
}

void WaylandCompositor::sendNativeBack(int surfaceId, bool keelHosted) {
    QWaylandSurface *surface = m_surfaceMap.value(surfaceId);
    if (!surface || !surface->client()) {
        emit nativeBackUnhandled(surfaceId);
        return;
    }

    // The client handles back itself, popups and dialogs included.
    if (MarathonSurfaceV1 *marathon = m_marathonSurfaceManager->forSurface(surface)) {
        watchNativeBack(surface, surfaceId);
        marathon->sendBackCommitted();
        return;
    }

    // Transient UI goes first, through the protocol rather than a key the
    // focused widget might take: the app's newest popup, else its newest
    // child window.
    QWaylandXdgPopup    *popup  = nullptr;
    QWaylandXdgToplevel *dialog = nullptr;
    for (auto it = m_xdgSurfaceMap.constBegin(); it != m_xdgSurfaceMap.constEnd(); ++it) {
        const QWaylandXdgSurface *xdg = it.value();
        if (!xdg || !xdg->surface() || xdg->surface() == surface ||
            xdg->surface()->client() != surface->client() || !xdg->surface()->hasContent())
            continue;
        if (xdg->popup())
            popup = xdg->popup();
        else if (xdg->toplevel() && xdg->toplevel()->parentToplevel())
            dialog = xdg->toplevel();
    }
    if (popup) {
        watchNativeBack(surface, surfaceId);
        popup->sendPopupDone();
        return;
    }
    if (dialog) {
        watchNativeBack(surface, surfaceId);
        dialog->sendClose();
        return;
    }

    QVariant toolkit = surface->property("nativeToolkit");
    if (!toolkit.isValid()) {
        QFile maps(QStringLiteral("/proc/%1/maps").arg(surface->client()->processId()));
        toolkit = int(maps.open(QIODevice::ReadOnly) ? NativeBack::toolkitFromMaps(maps.readAll()) :
                                                       NativeBack::Unknown);
        surface->setProperty("nativeToolkit", toolkit);
    }
    QPointer<QWaylandSurface> target(surface);
    sendKeyTo(surface, NativeBack::backKey(NativeBack::Toolkit(toolkit.toInt()), keelHosted),
              Qt::NoModifier, [this, target, surfaceId]() {
                  if (target)
                      watchNativeBack(target, surfaceId);
              });
}

void WaylandCompositor::sendBackProgress(int surfaceId, qreal progress,
                                         const QPointF &scenePosition) {
    QWaylandSurface   *surface  = m_surfaceMap.value(surfaceId);
    MarathonSurfaceV1 *marathon = m_marathonSurfaceManager->forSurface(surface);
    if (!marathon)
        return;
    QPointF position;
    if (const QWaylandView *view = surface->primaryView()) {
        if (const auto *item = qobject_cast<const QWaylandQuickItem *>(view->renderObject()))
            position = item->mapToSurface(item->mapFromScene(scenePosition));
    }
    // The pill swipe moves leftwards, as a swipe in from the right edge does.
    marathon->sendBackProgress(MARATHON_SURFACE_V1_BACK_EDGE_RIGHT, progress, position);
}

void WaylandCompositor::endBackGesture(int surfaceId) {
    if (MarathonSurfaceV1 *marathon =
            m_marathonSurfaceManager->forSurface(m_surfaceMap.value(surfaceId)))
        marathon->cancelBack();
}

void WaylandCompositor::sendNativeForward(int surfaceId, bool keelHosted) {
    QWaylandSurface *surface = m_surfaceMap.value(surfaceId);
    if (!surface || !surface->client())
        return;
    if (keelHosted)
        sendKeyTo(surface, Qt::Key_Right, Qt::AltModifier);
    else
        sendKeyTo(surface, Qt::Key_Forward, Qt::NoModifier);
}

// Wayland has no reply to a key: back counts as handled once the app shows a
// change, and as unhandled if the watch window passes without one.
void WaylandCompositor::watchNativeBack(QWaylandSurface *surface, int surfaceId) {
    static const int watchMs = [] {
        bool      ok = false;
        const int ms = qEnvironmentVariableIntValue("MARATHON_NATIVE_BACK_MS", &ok);
        return ok && ms > 0 ? ms : NativeBack::kWatchMs;
    }();
    auto      *watch   = new QObject(this);
    auto       settled = std::make_shared<bool>(false);
    const auto changed = [watch, settled]() {
        *settled = true;
        watch->deleteLater();
    };
    connect(surface, &QWaylandSurface::damaged, watch, [surface, changed](const QRegion &damage) {
        if (NativeBack::visibleChange(damage, surface->destinationSize()))
            changed();
    });
    connect(surface, &QWaylandSurface::surfaceDestroyed, watch, changed);
    // Its subsurfaces draw for it too: Waydroid's toplevel is an empty 1x1
    // with Android's layers in subsurfaces.
    if (const QWaylandView *view = surface->primaryView()) {
        QList<QQuickItem *> items{qobject_cast<QQuickItem *>(view->renderObject())};
        while (!items.isEmpty()) {
            QQuickItem *item = items.takeLast();
            if (!item)
                continue;
            items.append(item->childItems());
            auto *sub = qobject_cast<QWaylandQuickItem *>(item);
            if (!sub || !sub->surface() || sub->surface() == surface)
                continue;
            QWaylandSurface *subsurface = sub->surface();
            connect(subsurface, &QWaylandSurface::damaged, watch,
                    [subsurface, changed](const QRegion &damage) {
                        if (NativeBack::visibleChange(damage, subsurface->destinationSize()))
                            changed();
                    });
        }
    }
    if (auto *toplevel = surface->property("xdgToplevel").value<QWaylandXdgToplevel *>())
        connect(toplevel, &QWaylandXdgToplevel::titleChanged, watch, changed);
    QWaylandClient *client = surface->client();
    for (const QPointer<QWaylandSurface> &other : std::as_const(m_surfaceMap)) {
        if (other && other != surface && other->client() == client) {
            connect(other, &QWaylandSurface::hasContentChanged, watch, changed);
            connect(other, &QWaylandSurface::surfaceDestroyed, watch, changed);
        }
    }
    connect(this, &QWaylandCompositor::surfaceCreated, watch,
            [client, changed](QWaylandSurface *created) {
                if (created->client() == client)
                    changed();
            });
    QTimer::singleShot(watchMs, watch, [this, watch, settled, surfaceId]() {
        if (!*settled)
            emit nativeBackUnhandled(surfaceId);
        watch->deleteLater();
    });
}

// The key reaches the app's window even when another holds keyboard focus.
// Another window of the same client (Waydroid's Android tasks) takes it only
// once it has acted on the enter: at its next commit, or after 300 ms.
void WaylandCompositor::sendKeyTo(QWaylandSurface *surface, int key,
                                  Qt::KeyboardModifiers modifiers,
                                  const std::function<void()> &sent) {
    const auto send = [this, key, modifiers, sent]() {
        injectKey(key, int(modifiers), true);
        injectKey(key, int(modifiers), false);
        if (sent)
            sent();
    };
    QWaylandSeat          *seat  = defaultSeat();
    const QWaylandSurface *focus = seat ? seat->keyboardFocus() : nullptr;
    if (!seat || focus == surface) {
        send();
        return;
    }
    seat->setKeyboardFocus(surface);
    if (!focus || focus->client() != surface->client()) {
        send();
        return;
    }
    auto *wait = new QObject(this);
    auto  once = [wait, send, seat, target = QPointer<QWaylandSurface>(surface)]() {
        if (wait->property("done").toBool())
            return;
        wait->setProperty("done", true);
        wait->deleteLater();
        if (target && seat->keyboardFocus() == target)
            send();
    };
    connect(surface, &QWaylandSurface::redraw, wait, once);
    QTimer::singleShot(300, wait, once);
}

bool WaylandCompositor::checkIdleInhibitors() {
    bool hasInhibitor = false;

    for (auto it = m_surfaceMap.constBegin(); it != m_surfaceMap.constEnd(); ++it) {
        QWaylandSurface *surface = it.value();
        // The protocol only honours an inhibitor while its surface is mapped.
        if (surface && surface->inhibitsIdle() && surface->hasContent()) {
            qDebug() << "[WaylandCompositor] Surface" << it.key() << "inhibits idle";
            hasInhibitor = true;
            break;
        }
    }

    if (hasInhibitor != m_hasIdleInhibitor) {
        m_hasIdleInhibitor = hasInhibitor;
        emit hasIdleInhibitingSurfaceChanged();
        qDebug() << "[WaylandCompositor] Idle inhibitor state changed:" << hasInhibitor;
    }

    return hasInhibitor;
}

QString WaylandCompositor::focusedToolkit() const {
    const QWaylandSurface *focus = defaultSeat() ? defaultSeat()->keyboardFocus() : nullptr;
    if (!focus || !m_appRegistry)
        return {};
    const QString appId = focus->property("appId").toString();
    return appId.isEmpty() ? QString() : m_appRegistry->getApp(appId).value("toolkit").toString();
}

qint64 WaylandCompositor::monotonicUs() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000 + ts.tv_nsec / 1000;
}

// The time of the CRTC's last vblank, or -1 (no fd, or the display is off).
qint64 WaylandCompositor::lastVblankUs() {
    if (!initAtomicDisplay())
        return -1;
    drmVBlank vbl{};
    vbl.request.type     = drmVBlankSeqType(DRM_VBLANK_RELATIVE);
    vbl.request.sequence = 0;
    if (drmWaitVBlank(m_driFd, &vbl) != 0)
        return -1;
    return qint64(vbl.reply.tval_sec) * 1000000 + vbl.reply.tval_usec;
}

qint64 WaylandCompositor::frameLatchUs() {
    const qint64 last = lastVblankUs();
    if (last < 0)
        return -1;
    return last + qint64(m_framePhaseMs) * 1000;
}

qint64 WaylandCompositor::nextVblankUs() {
    const qint64 last = lastVblankUs();
    if (last < 0)
        return -1;
    const qreal  hz     = m_window && m_window->screen() ? m_window->screen()->refreshRate() : 60.0;
    const qint64 period = qint64(1000000.0 / (hz > 0 ? hz : 60.0));
    qint64       next   = last + period;
    while (next < monotonicUs())
        next += period;
    return next;
}

bool WaylandCompositor::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window && m_framePhaseMs > 0 && event->type() == QEvent::UpdateRequest) {
        if (m_passUpdate) {
            m_passUpdate = false;
            return false;
        }
        if (m_gateTimer.isActive())
            return true;
        const qint64 now    = monotonicUs();
        const qint64 last   = lastVblankUs();
        const qint64 at     = last + qint64(m_framePhaseMs) * 1000;
        if (last >= 0 && now < at - 500) {
            m_gateTimer.start(int((at - now) / 1000));
            return true;
        }
    }
    if (watched == m_window) {
        const auto type = event->type();
        // Emit userActivity() on any human-input signal — not just the
        // edge-triggered Begin/Press events. Without TouchUpdate /
        // MouseMove we miss "user is scrolling / dragging in the
        // foreground app" which is the dominant interaction pattern;
        // the idle-screen-off timer then fires mid-gesture. Wheel +
        // KeyRelease are belt-and-braces for kbd-only paths.
        // A move only refreshes timers measured in seconds: at most every
        // 250 ms, not on each touch report (three QML slots ran per event).
        const bool edge = type == QEvent::TouchBegin || type == QEvent::MouseButtonPress ||
            type == QEvent::KeyPress || type == QEvent::KeyRelease;
        const bool move =
            type == QEvent::TouchUpdate || type == QEvent::MouseMove || type == QEvent::Wheel;
        if (edge || (move && (!m_activityEmitted.isValid() || m_activityEmitted.elapsed() >= 250))) {
            m_activityEmitted.start();
            emit userActivity();
        }
        if (type == QEvent::TouchBegin || type == QEvent::MouseButtonPress ||
            type == QEvent::KeyPress) {
            m_xdgActivation->noteUserInput();
            m_lastUserInput.start();
        }

        if (type == QEvent::KeyPress || type == QEvent::KeyRelease) {
            const auto *keyEvent = static_cast<QKeyEvent *>(event);
            const KeyRouting::Action action =
                KeyRouting::systemAction(keyEvent->key(), focusedToolkit());
            if (action != KeyRouting::None) {
                if (type == QEvent::KeyRelease) {
                    if (action == KeyRouting::Back)
                        emit systemBackTriggered();
                    else
                        emit systemHomeTriggered();
                }
                return true;
            }
        }
    }

    return QObject::eventFilter(watched, event);
}

void WaylandCompositor::sendSuspendedState(const QString &appId, bool suspended) {
    if (appId.isEmpty())
        return;

    // xdg-shell v6 state code (Qt 6.10's public State enum stops at
    // ActivatedState=4; the wire protocol number is in
    // qwayland-server-xdg-shell.h:state_suspended=9).
    constexpr int        kStateSuspended = 9;

    QWaylandXdgToplevel *toplevel = nullptr;
    int                  foundId  = -1;
    for (auto it = m_xdgSurfaceMap.constBegin(); it != m_xdgSurfaceMap.constEnd(); ++it) {
        QWaylandXdgSurface *xdgSurface = it.value();
        if (!xdgSurface || !xdgSurface->surface())
            continue;
        if (xdgSurface->surface()->property("appId").toString() != appId)
            continue;
        auto *candidate =
            xdgSurface->surface()->property("xdgToplevel").value<QWaylandXdgToplevel *>();
        if (!candidate)
            continue;
        toplevel = candidate;
        // clang-analyzer can't see the qInfo() << foundId read through QDebug's
        // stream operator, so it flags this store as dead. The qInfo line below
        // is the read; the value is genuinely used.
        foundId = it.key(); // NOLINT(clang-analyzer-deadcode.DeadStores)
        break;
    }
    if (!toplevel)
        return;

    QList<int> states;
    if (toplevel->activated())
        states << static_cast<int>(QWaylandXdgToplevel::ActivatedState);
    if (toplevel->maximized())
        states << static_cast<int>(QWaylandXdgToplevel::MaximizedState);
    if (toplevel->fullscreen())
        states << static_cast<int>(QWaylandXdgToplevel::FullscreenState);
    if (toplevel->resizing())
        states << static_cast<int>(QWaylandXdgToplevel::ResizingState);
    if (suspended)
        states << kStateSuspended;

    // Keep the size the client already has; a different one would relayout it on every resume.
    QWaylandSurface *surface = toplevel->xdgSurface()->surface();
    QSize            size    = surface->destinationSize();
    if (size.isEmpty())
        size = appConfigureSize(surface);
    toplevel->sendConfigure(size, states);
    qInfo() << "[WaylandCompositor] xdg-suspend appId=" << appId << "suspended=" << suspended
            << "surfaceId=" << foundId;
}
