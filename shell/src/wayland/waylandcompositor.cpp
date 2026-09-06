#include "src/wayland/waylandcompositor.h"
#include "src/wayland/committimingv1.h"
#include "src/wayland/fifov1.h"
#include "src/wayland/linuxdmabufv1.h"
#include "src/wayland/wldrm.h"
#include "src/wayland/securitycontextv1.h"
#include "src/wayland/textinputv3.h"
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
#include <QWaylandInputMethodControl>
#include <QWaylandQuickSurface>
#include <QtMath>
#include <QQuickItem>
#include <QKeyEvent>
#include <QScreen>
#include <QGuiApplication>
#include <qpa/qplatformnativeinterface.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <cstring>
#include "textinputv3.h"

#include "util/frametiming.h"
#include "util/rtprio.h"
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

    m_textInputManagerV3Custom = new TextInputManagerV3(this);
    connect(m_textInputManagerV3Custom, &TextInputManagerV3::textInputEnabled, this,
            [this](QWaylandSurface *) { emit nativeTextInputPanelRequested(true); });
    connect(m_textInputManagerV3Custom, &TextInputManagerV3::textInputDisabled, this,
            [this](QWaylandSurface *) { emit nativeTextInputPanelRequested(false); });

    // wp_security_context_v1 — lets sandbox engines (marathon-app-runner,
    // future Flatpak) tag connections with a fixed (engine, app_id,
    // instance_id) triple. The compositor (and any portal proxies that
    // consult it) can then enforce per-app policy independent of the
    // client's own assertion. Runtime wiring (marathon-app-runner using
    // this to make its bwrap'd apps connect on a separate FD) lands in a
    // follow-up commit; this enables the global so the runtime side can
    // be developed against a real implementation.
    m_securityContextManager = new SecurityContextManagerV1(this);

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
                new QWaylandQuickSurface(this, client, id, version);
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

    // ── Present pipeline (opt-in: MARATHON_PRESENT_PIPELINE) ──────────
    // Default QtWayland throttles client scroll to ~15fps on this in-process
    // compositor: it sends wl_surface.frame callbacks from afterRendering
    // (frame END, cross-thread-queued to the GUI loop) and the on-demand
    // threaded render loop sleeps between frames, so a client's commit waits
    // ~1 vblank to be scheduled and its callback arrives only after our frame
    // -- a serialized ~4-vblank round trip (measured: client swap blocks
    // ~67ms, both sides idle). This collapses it to a 1-frame pipeline.
    m_presentPipeline = envBool("MARATHON_PRESENT_PIPELINE", false);
    if (m_presentPipeline && m_window && m_output) {
        m_output->setAutomaticFrameCallback(false);
        // beforeSynchronizing runs on the render thread while the GUI thread
        // is blocked in sync -- the safe point to touch wl_display. Sending
        // the frame callback here (frame START, before our own present) hands
        // the client the full frame interval to render its next buffer
        // concurrently, instead of only after our frame completes.
        connect(
            m_window, &QQuickWindow::beforeSynchronizing, this,
            [this]() {
                if (m_output)
                    m_output->sendFrameCallbacks();
            },
            Qt::DirectConnection);
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
        qInfo() << "[WaylandCompositor] Present pipeline ENABLED (early frame "
                   "callbacks + commit-gated vsync free-run)";
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

    // AUTO-LAUNCH TEST: only kick off if the optional dev helper is installed.
    QTimer::singleShot(15000, this, [this]() {
        if (QFile::exists("/usr/bin/marathon-app-debug")) {
            qInfo() << "[WaylandCompositor] Auto-launching debug app";
            launchApp("/usr/bin/marathon-app-debug");
        }
    });
}

WaylandCompositor::~WaylandCompositor() {
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

QQmlListProperty<QObject> WaylandCompositor::surfaces() {
    return QQmlListProperty<QObject>(this, &m_surfaces);
}

void WaylandCompositor::launchApp(const QString &command, const QVariantMap &extraEnv) {
    if (command.isEmpty()) {
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
            newParts << "flatpak"
                     << "run"
                     << "--socket=wayland"
                     << QStringLiteral("--filesystem=xdg-run/%1").arg(socketName())
                     << QStringLiteral("--env=WAYLAND_DISPLAY=%1").arg(socketName());
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
    QString runtimeDir = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR"));

    if (runtimeDir.isEmpty()) {
        qWarning() << "[WaylandCompositor] XDG_RUNTIME_DIR not set! Apps may fail to connect.";
        runtimeDir = "/tmp";
    }

    env.remove("WAYLAND_DISPLAY");
    env.remove("DISPLAY");

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

    if (actualCommand.contains("marathon-app-runner")) {
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
    connect(process, &QProcess::readyReadStandardOutput, this, [safeProcess, command]() {
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
                    qWarning().noquote() << "[AppRunner stdout]" << command << "->" << line;
                    if (++shown >= 25)
                        break;
                }
            }
        }
    });

    connect(process, &QProcess::readyReadStandardError, this, [safeProcess, command]() {
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
                    qWarning().noquote() << "[AppRunner stderr]" << command << "->" << line;
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

    const bool    useSandbox = !isFlatpak && !isSnap && envBool("MARATHON_ENABLE_SANDBOX", false);

    const QString dbusConfigPath = runtimeDir + "/marathon-dbus-restricted.conf";
    if (useSandbox && !isRunner) {
        QFile f(dbusConfigPath);
        if (f.open(QIODevice::WriteOnly)) {
            QTextStream out(&f);
            out << "<busconfig>\n";
            out << "  <type>session</type>\n";
            out << "  <listen>unix:tmpdir=/tmp</listen>\n";
            out << "  <policy context=\"default\">\n";
            out << "    <allow send_destination=\"*\" eavesdrop=\"true\"/>\n";
            out << "    <allow receive_sender=\"*\" eavesdrop=\"true\"/>\n";
            out << "    <allow own=\"*\"/>\n";
            out << "  </policy>\n";
            out << "</busconfig>\n";
            f.close();
        }
    }

    QString       sandboxPath = QStringLiteral("marathon-sandbox");
    const QDir    shellBinDir(QCoreApplication::applicationDirPath());
    const QString devSandboxPath =
        shellBinDir.filePath("../tools/marathon-sandbox/marathon-sandbox");
    if (QFile::exists(devSandboxPath)) {
        sandboxPath = devSandboxPath;
    }

    if (!needsShell) {
        if (useSandbox) {
            QStringList finalArgs;
            QString     finalProgram;
            if (!isRunner) {
                finalProgram = "dbus-run-session";
                finalArgs << "--config-file" << dbusConfigPath << "--" << sandboxPath << program
                          << args;
            } else {
                finalProgram = sandboxPath;
                finalArgs << program << args;
            }
            process->setProgram(finalProgram);
            process->setArguments(finalArgs);
        } else {
            process->setProgram(program);
            process->setArguments(args);
        }
        process->start();
    } else {
        if (useSandbox) {
            if (!isRunner) {
                process->start("dbus-run-session",
                               {"--config-file", dbusConfigPath, "--", sandboxPath, "/bin/sh", "-c",
                                actualCommand});
            } else {
                process->start(sandboxPath, {"/bin/sh", "-c", actualCommand});
            }
        } else {
            process->start("/bin/sh", {"-c", actualCommand});
        }
    }
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

void WaylandCompositor::handleSurfaceCreated(QWaylandSurface *surface) {
    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Surface created:" << surface;

    connect(surface, &QWaylandSurface::surfaceDestroyed, this,
            &WaylandCompositor::handleSurfaceDestroyed);

    // Client commit meter (harmless when the 1Hz stats timer isn't running).
    connect(surface, &QWaylandSurface::redraw, this,
            [this]() { m_clientCommitCount.fetchAndAddRelaxed(1); });

    if (m_presentPipeline) {
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

    if (auto *inputControl = surface->inputMethodControl()) {
        qDebug() << "[WaylandCompositor] Connected to inputMethodControl for surface";
        // QWaylandInputMethodControl::enabledChanged isn't exported in the public
        // Qt build, so the Qt5 pointer-to-member form fails to link. The SIGNAL/
        // SLOT macro form uses MOC's string dispatch and works without the symbol.
        connect(inputControl, SIGNAL(enabledChanged(bool)), this,
                SLOT(handleTextInputEnabled(bool)));
    } else {
        qDebug() << "[WaylandCompositor] No inputMethodControl available for surface";
    }

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
    if (surface && defaultSeat()) {
        defaultSeat()->setKeyboardFocus(surface);
        if (wlVerbose())
            qDebug() << "[WaylandCompositor] Activated surface (set keyboard focus):" << surfaceId;
    } else {
        qWarning() << "[WaylandCompositor] Failed to activate surface:" << surfaceId;
    }
}

// A minimized surface's views stop delivering wl_surface.frame callbacks,
// so a throttled client never commits again — and a restored view with no
// current buffer paints nothing, which never resumes the callbacks either.
// Firing the pending callbacks breaks that deadlock at restore.
void WaylandCompositor::nudgeSurface(int surfaceId) {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(getSurfaceById(surfaceId));
    if (!surface)
        return;
    // Callbacks alone only unblock a client already waiting mid-frame; an
    // idle client needs a reason to redraw before a fresh view can take a
    // buffer. A same-state configure forces ack + commit, like restore does.
    surface->sendFrameCallbacks();
    QWaylandXdgSurface *xdg = m_xdgSurfaceMap.value(surfaceId);
    if (xdg && xdg->toplevel()) {
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
}

void WaylandCompositor::handleTextInputEnabled(bool enabled) {
    emit nativeTextInputPanelRequested(enabled);
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

    // Send an initial xdg_toplevel.configure as soon as the toplevel is created
    // so the client can ack + commit its first content buffer. The QML side
    // (WaylandShellSurfaceItem.sendSizeToApp) only fires after the surface item
    // gets a non-zero size, which depends on layout/loader timing -- the
    // surface can sit unconfigured for arbitrarily long, and Qt's qtwayland
    // client decides "window inexposed" and stops painting. By sending the
    // output size up-front, the client always gets a first configure within
    // milliseconds of mapping and can proceed to attach + commit its buffer.
    if (m_output && m_output->window()) {
        const QSize outputSize = m_output->window()->size();
        if (outputSize.width() > 0 && outputSize.height() > 0) {
            QList<QWaylandXdgToplevel::State> states;
            states << QWaylandXdgToplevel::ActivatedState << QWaylandXdgToplevel::MaximizedState;
            toplevel->sendConfigure(outputSize, states);
            qInfo() << "[WaylandCompositor] Sent initial configure" << outputSize << "for surfaceId"
                    << surfaceId;
        }
    }

    emit                          surfaceCreated(surface, surfaceId, xdgSurface);

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

    QSize physicalSizeMm(0, 0);
    if (screen) {
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
    static const bool enabled = envBool("MARATHON_DOZE_DPMS", true);
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

bool WaylandCompositor::checkIdleInhibitors() {
    bool hasInhibitor = false;

    for (auto it = m_surfaceMap.constBegin(); it != m_surfaceMap.constEnd(); ++it) {
        QWaylandSurface *surface = it.value();
        if (surface && surface->inhibitsIdle()) {
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

bool WaylandCompositor::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window) {
        const auto type = event->type();
        // Emit userActivity() on any human-input signal — not just the
        // edge-triggered Begin/Press events. Without TouchUpdate /
        // MouseMove we miss "user is scrolling / dragging in the
        // foreground app" which is the dominant interaction pattern;
        // the idle-screen-off timer then fires mid-gesture. Wheel +
        // KeyRelease are belt-and-braces for kbd-only paths.
        if (type == QEvent::TouchBegin || type == QEvent::TouchUpdate ||
            type == QEvent::MouseButtonPress || type == QEvent::MouseMove ||
            type == QEvent::Wheel || type == QEvent::KeyPress || type == QEvent::KeyRelease) {
            emit userActivity();
        }

        if (type == QEvent::KeyPress || type == QEvent::KeyRelease) {
            QKeyEvent *keyEvent = static_cast<QKeyEvent *>(event);
            int        key      = keyEvent->key();

            if (key == Qt::Key_Escape || key == Qt::Key_Super_L || key == Qt::Key_Meta) {
                if (type == QEvent::KeyPress) {
                    return true;
                }
                if (type == QEvent::KeyRelease) {
                    if (key == Qt::Key_Escape) {
                        emit systemBackTriggered();
                    } else {
                        emit systemHomeTriggered();
                    }
                    return true;
                }
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

    const QSize size = (m_output && m_output->window()) ? m_output->window()->size() : QSize(0, 0);
    toplevel->sendConfigure(size, states);
    qInfo() << "[WaylandCompositor] xdg-suspend appId=" << appId << "suspended=" << suspended
            << "surfaceId=" << foundId;
}
