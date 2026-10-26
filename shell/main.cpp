#include <cmath>
#include <QClipboard>
#include <QGuiApplication>
#include <QScreen>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QDebug>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QStandardPaths>
#include <QLoggingCategory>
#include <QInputDevice>
#include <QFutureWatcher>
#include <QtConcurrent/QtConcurrentRun>
#include <functional>
#include <memory>
#include <QDBusMetaType>
#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QSurfaceFormat>
#include <QColorSpace>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>

#include "marathon-shell-native/src/app_ids.cxxqt.h"
#include "marathon-shell-native/src/rt.cxxqt.h"
#include <cstdio>
#include <cstring>

#include <QSocketNotifier>
#include <csignal>
#include <unistd.h>
#include <fcntl.h>

#include "marathon-shell-native/src/desktop.cxxqt.h"
#include "marathon-shell-native/src/sandbox.cxxqt.h"
#include "marathon-shell-native/src/apps.cxxqt.h"
#include "marathon-shell-native/src/tasks.cxxqt.h"
#include "marathon-shell-native/src/ipc.cxxqt.h"
#include "marathon-shell-native/src/alarms.cxxqt.h"
#include "src/services/gesturetracker.h"
#include "src/components/windowtextureitem.h"
#include "src/components/backdropprobe.h"
#include "src/services/waketouchfilter.h"
#include "marathon-shell-native/src/pressure.cxxqt.h"
#include "marathon-shell-native/src/notifications.cxxqt.h"
#include "marathon-shell-native/src/push.cxxqt.h"
#include "marathon-shell-native/src/timezone.cxxqt.h"
#include "marathon-shell-native/src/network.cxxqt.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include "marathon-shell-native/src/device.cxxqt.h"
#include "marathon-shell-native/src/display.cxxqt.h"
#include "src/services/wakeonkeyfilter.h"
#include "marathon-shell-native/src/pilot.cxxqt.h"
#include "marathon-shell-native/src/weather.cxxqt.h"
#include "src/services/inputboost.h"
#include "src/services/touchresampler.h"
#include "marathon-shell-native/src/audio.cxxqt.h"
#include "marathon-shell-native/src/modem.cxxqt.h"
#include "marathon-shell-native/src/settings.cxxqt.h"
#include "marathon-shell-native/src/i18n.cxxqt.h"
#include "src/services/translations.h"
#include "marathon-shell-native/src/ambience.cxxqt.h"
#include "marathon-shell-native/src/ngf.cxxqt.h"
#include "marathon-shell-native/src/portal.cxxqt.h"
#include "marathon-shell-native/src/file_model.cxxqt.h"
#include "marathon-shell-native/src/bluetooth.cxxqt.h"
#include "marathon-shell-native/src/gate.cxxqt.h"
#include "marathon-shell-native/src/permissions.cxxqt.h"
#include "marathon-shell-native/src/updates.cxxqt.h"
#include "src/wayland/waylandcompositormanager.h"
#include "src/managers/marathoninputmethodengine.h"
#include "src/managers/cursormanager.h"
#include "src/components/svgimageprovider.h"

#include "marathon-shell-native/src/mpris.cxxqt.h"
#include "marathon-shell-native/src/location.cxxqt.h"
#include "marathon-shell-native/src/clipboard.cxxqt.h"
#include "marathon-shell-native/src/haptics.cxxqt.h"
#include "marathon-shell-native/src/flashlight.cxxqt.h"
#include "marathon-shell-native/src/security.cxxqt.h"
#include "marathon-shell-native/src/contacts.cxxqt.h"
#include "marathon-shell-native/src/telephonyd.cxxqt.h"
#include "src/managers/screenmetrics.h"
#include "marathon-shell-native/src/links.cxxqt.h"
#include "marathon-shell-native/src/layouts.cxxqt.h"
#include "marathon-shell-native/src/search.cxxqt.h"
#include "src/services/screenshotservicecpp.h"
#include "marathon-shell-native/src/session.cxxqt.h"
#include "marathon-shell-native/src/ui.cxxqt.h"
#include "marathon-shell-native/src/share.cxxqt.h"
#include "src/services/inputcontext.h"
#include "src/services/remotetextinput.h"
#include "marathon-shell-native/src/text_input.cxxqt.h"
#include "marathon-shell-native/src/words.cxxqt.h"
#include <QDBusConnection>

#ifdef HAVE_WAYLAND
#include "src/wayland/waylandcompositor.h"
#include "src/wayland/nativeclientscale.h"
#include "src/wayland/nativesurfaceitem.h"
#include "src/diag/fpsmonitor.h"
#include <QWaylandSurface>
#include <QWaylandXdgShell>
#include "src/wayland/remotetextinputtarget.h"
#include "src/wayland/foreignfocus.h"
#include <QtWaylandCompositor/QWaylandClient>
#include <QtWaylandCompositor/QWaylandXdgSurface>
#include <QtWaylandCompositor/QWaylandXdgToplevel>
#endif

#ifdef MARATHON_HAVE_INPUT_SUPPORT
#include "src/services/touchdevices.h"
#include <QtDeviceDiscoverySupport/private/qdevicediscovery_p.h>
#include <QtGui/private/qguiapplication_p.h>
#include <QtGui/private/qinputdevicemanager_p_p.h>
#include <QtInputSupport/private/qevdevtouchhandler_p.h>
#include <QtInputSupport/private/qevdevutil_p.h>
// Where Qt defines it; outside Qt's build the header declares a global one.
namespace QtPrivateLogging {
    const QLoggingCategory &qLcEvdevTouch();
}
#endif

template <typename T, typename... Args>
static T *createObject(QQmlContext *ctx, const char *qmlName, Args &&...args) {
    static_assert(std::is_base_of_v<QObject, T>, "T must inherit QObject");

    T *obj = new T(std::forward<Args>(args)...);
    ctx->setContextProperty(qmlName, obj);
    return obj;
}

#ifdef HAVE_WAYLAND
// The compositor's processes and windows, told to the tasks; what the
// tasks ask of the compositor, done.
static void connectTasks(Tasks *tasks, WaylandCompositor *wc) {
    wc->setSecureApps(tasks->getSecureApps());
    QObject::connect(tasks, &Tasks::secureAppsChanged, wc,
                     [=] { wc->setSecureApps(tasks->getSecureApps()); });
    const auto viewport = [=] {
        tasks->setAppViewport(wc->appViewportSize().width(), wc->appViewportSize().height());
    };
    viewport();
    QObject::connect(wc, &WaylandCompositor::appViewportSizeChanged, tasks, viewport);
    QObject::connect(tasks, &Tasks::spawnRequested, wc,
                     [=](const QString &command, const QVariantMap &env) { wc->launchApp(command, env); });
    QObject::connect(tasks, &Tasks::closeWindowRequested, wc, &WaylandCompositor::closeWindow);
    QObject::connect(tasks, &Tasks::sandboxSocketRequested, wc,
                     [=](const QString &appId, const QString &instance) { wc->openSandboxSocket(appId, instance); });
    QObject::connect(tasks, &Tasks::sandboxSocketClosed, wc, &WaylandCompositor::closeSandboxSocket);
    QObject::connect(tasks, &Tasks::sandboxAppAssigned, wc, &WaylandCompositor::assignSandboxApp);
    QObject::connect(tasks, &Tasks::nativeBackRequested, wc, &WaylandCompositor::sendNativeBack);
    QObject::connect(tasks, &Tasks::nativeForwardRequested, wc, &WaylandCompositor::sendNativeForward);

    QObject::connect(wc, &WaylandCompositor::appLaunched, tasks,
                     [=](const QString &command, int pid) { tasks->appLaunched(command, pid); });
    QObject::connect(wc, &WaylandCompositor::appClosed, tasks, [=](int pid) { tasks->appClosed(pid); });
    QObject::connect(wc, &WaylandCompositor::nativeBackUnhandled, tasks, &Tasks::nativeBackUnhandled);
    QObject::connect(wc, &WaylandCompositor::surfaceDestroyed, tasks,
                     [=](QWaylandSurface *, int surfaceId) { tasks->windowDestroyed(surfaceId); });
    QObject::connect(wc, &WaylandCompositor::surfaceActivated, tasks,
                     [=](QWaylandSurface *, int surfaceId, QWaylandXdgSurface *, qint64 launchPid) {
                         tasks->windowActivated(surfaceId, launchPid);
                     });
    const auto clientPid = [](QWaylandSurface *surface) -> qint64 {
        return surface && surface->client() ? surface->client()->processId() : -1;
    };
    QObject::connect(wc, &WaylandCompositor::dialogCreated, tasks,
                     [=](QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *) {
                         tasks->dialogMapped(clientPid(surface), wc->sandboxAppId(surface->client()->client()), surfaceId);
                     });
    QObject::connect(
        wc, &WaylandCompositor::surfaceCreated, tasks,
        [=](QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdg) {
            if (!surface)
                return;
            const qint64  pid       = clientPid(surface);
            const QString sandboxId = surface->client() ? wc->sandboxAppId(surface->client()->client()) : QString();
            QString       xdgAppId, title;
            if (xdg && xdg->toplevel()) {
                xdgAppId = xdg->toplevel()->appId();
                title    = xdg->toplevel()->title();
            }
            const bool shown = tasks->windowMapped(pid, pid, xdgAppId, title, sandboxId, surfaceId,
                                                   wc->recentUserInput(2000));
            // Read by the compositor: the window's first configure, and
            // whether it may be configured only to change something.
            surface->setProperty("mappedInBackground", !shown);
            surface->setProperty("foreignClient", tasks->isForeignWindow(surfaceId));
            if (!shown)
                ForeignFocus::keepFront(wc->defaultSeat(), surface);
        });
}
#endif

#ifdef MARATHON_HAVE_INPUT_SUPPORT
// Qt's QEvdevTouchManager, except that a udev "add" for a node already read
// doesn't open it again.
static void startTouchInput(const QString &specification) {
    if (qEnvironmentVariableIsSet("QT_QPA_EVDEV_DEBUG"))
        const_cast<QLoggingCategory &>(QtPrivateLogging::qLcEvdevTouch())
            .setEnabled(QtDebugMsg, true);
    QString spec = qEnvironmentVariable("QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS");
    if (spec.isEmpty())
        spec = specification;
    const auto parsed = QEvdevUtil::parseSpecification(spec);

    const auto devices = new TouchDevices(
        [handlerSpec = parsed.spec](const QString &node) {
            return std::unique_ptr<QObject>(new QEvdevTouchScreenHandlerThread(node, handlerSpec));
        },
        qApp);
    const auto updateCount = [devices] {
        int registered = 0;
        for (QObject *handler : devices->handlers())
            registered += static_cast<QEvdevTouchScreenHandlerThread *>(handler)
                              ->isPointingDeviceRegistered();
        QInputDeviceManagerPrivate::get(QGuiApplicationPrivate::inputDeviceManager())
            ->setDeviceCount(QInputDeviceManager::DeviceTypeTouch, registered);
    };
    const auto add = [devices, updateCount](const QString &node) {
        if (auto *handler = static_cast<QEvdevTouchScreenHandlerThread *>(devices->add(node)))
            QObject::connect(handler, &QEvdevTouchScreenHandlerThread::touchDeviceRegistered,
                             devices, updateCount);
    };

    for (const QString &node : parsed.devices)
        add(node);
    if (!parsed.devices.isEmpty())
        return;
    QDeviceDiscovery *discovery = QDeviceDiscovery::create(
        QDeviceDiscovery::Device_Touchpad | QDeviceDiscovery::Device_Touchscreen, devices);
    if (!discovery)
        return;
    for (const QString &node : discovery->scanConnectedDevices())
        add(node);
    QObject::connect(discovery, &QDeviceDiscovery::deviceDetected, devices, add);
    QObject::connect(discovery, &QDeviceDiscovery::deviceRemoved, devices,
                     [devices, updateCount](const QString &node) {
                         if (devices->remove(node))
                             updateCount();
                     });
}
#endif

static QFile       *logFile   = nullptr;
static QTextStream *logStream = nullptr;
// Function-local: a namespace-scope QMutex runs an initialiser before main()
// that can throw where nothing can catch it.
static QMutex &logMutex() {
    static QMutex m;
    return m;
}
static bool         g_debugEnabled = false;
static void         marathonMessageHandler(QtMsgType type, const QMessageLogContext &context,
                                           const QString &msg) {

    QMutexLocker locker(&logMutex());

    if (!g_debugEnabled && type == QtWarningMsg) {

        if ((msg.contains("Could not connect") &&
             (msg.contains("NetworkManager") || msg.contains("UPower"))) ||

            msg.contains("libEGL warning: failed to get driver name for fd -1") ||
            msg.contains("MESA-LOADER: failed to retrieve device information") ||
            msg.contains("Failed to initialize EGL display") ||
            // Qt6 prints this from libQt6Qml when the QML debugger code
            // path is linked, regardless of whether the build defined
            // QT_QML_DEBUG. It's noise in production. Filter unless the
            // user explicitly asked for debug output via $MARATHON_DEBUG.
            msg.contains("QML debugging is enabled")) {
            return;
        }
    }

    QString logLevel;
    switch (type) {
        case QtDebugMsg: logLevel = "DEBUG"; break;
        case QtInfoMsg: logLevel = "INFO"; break;
        case QtWarningMsg: logLevel = "WARNING"; break;
        case QtCriticalMsg: logLevel = "CRITICAL"; break;
        case QtFatalMsg: logLevel = "FATAL"; break;
    }

    QString timestamp  = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
    QString logMessage = QString("[%1] [%2] %3").arg(timestamp, logLevel, msg);

    if (context.file) {
        logMessage += QString(" (%1:%2)").arg(context.file).arg(context.line);
    }

    if (logStream && logFile && logFile->isOpen()) {
        (*logStream) << logMessage << "\n";

        if (g_debugEnabled || type >= QtWarningMsg) {
            logStream->flush();
        }
    }

    if (g_debugEnabled || type >= QtWarningMsg) {
        fprintf(stderr, "%s\n", qPrintable(logMessage));
    }

    if (type == QtFatalMsg) {
        if (logFile) {
            if (logStream) {
                logStream->flush();
                delete logStream;
                logStream = nullptr;
            }
            logFile->close();
            delete logFile;
            logFile = nullptr;
        }
        abort();
    }
}

#include <utility>   // std::as_const
#include <QtPlugin>

Q_IMPORT_PLUGIN(MarathonInputContextPlugin)

// MARATHON_STARTUP_TIMING=1: milliseconds since process start at each phase,
// to stderr (the journal) so no logging rule or handler buffer can drop it.
static void startupMark(const char *phase) {
    static const bool on = qEnvironmentVariableIntValue("MARATHON_STARTUP_TIMING") != 0;
    if (!on)
        return;
    static QElapsedTimer t = [] { QElapsedTimer e; e.start(); return e; }();
    fprintf(stderr, "[Startup] %lld ms %s\n", static_cast<long long>(t.elapsed()), phase);
}

int main(int argc, char *argv[]) {
    if (argc == 4 && std::strcmp(argv[1], "--rename-app-ids") == 0)
        return marathon::app_ids::rename_app_ids(argv[2], argv[3]);
    startupMark("main");

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");
    // QQmlApplicationEngine's file selector probes every URL for +locale and
    // +platform variants; the shell ships none. App launches strip it.
    qputenv("QT_NO_BUILTIN_SELECTORS", "1");

    // Curved-edge AA via geometry where FBO MSAA is unavailable. Etnaviv
    // (GC7000Lite) hides MSAA renderbuffers — without this Shape strokes,
    // squircle hairlines, and ShapePath outlines render aliased. Cost is
    // a few extra triangles per Shape; the scenegraph already supports
    // this code path. See doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph-renderer.html.
    if (!qEnvironmentVariableIsSet("QSG_ANTIALIASING_METHOD"))
        qputenv("QSG_ANTIALIASING_METHOD", "vertex");


    QString debugEnv     = qgetenv("MARATHON_DEBUG");
    bool    debugEnabled = (debugEnv == "1" || debugEnv.toLower() == "true");
    g_debugEnabled       = debugEnabled;

    QElapsedTimer timer;
    timer.start();
    if (debugEnabled) {
        qDebug() << "[Profiler] Startup begins...";
    }

    const QString profileEnv  = qgetenv("MARATHON_PROFILE");
    const bool    profileMode = (profileEnv == "1" || profileEnv.toLower() == "true");

    QGuiApplication::setApplicationName("Marathon Shell");
    QGuiApplication::setOrganizationName("Marathon OS");
    QGuiApplication::setApplicationVersion(QStringLiteral(MARATHON_VERSION));

    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents);

    // AA_ShareOpenGLContexts was previously set as an implicit side effect
    // of QtWebEngineQuick::initialize(). After the WebEngine refactor moved
    // that init to marathon-app-runner, the shell lost the attribute and
    // its QSG scenegraph hits a SIGSEGV on LLVMpipe at first-frame init
    // (reproduced in duranium r49 QEMU). Set it explicitly here so the
    // attribute stays even when the shell never imports WebEngine.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    // EGLFS allows exactly one top-level QWindow with one surface format
    // at a time. Any secondary QWindow with a different format triggers
    // "EGLFS: OpenGL windows cannot be mixed with others." → SIGABRT and
    // the shell dies. Suppress native sibling creation for QWidget-like
    // children (popups, tooltips, drag indicators) so the shell only
    // ever has the one main QQuickWindow. (Observed: every WebEngine
    // app launch was creating a second native window in the shell
    // process and abort-ing.)
    QCoreApplication::setAttribute(Qt::AA_DontCreateNativeWidgetSiblings);
    // Force every QML Popup / Menu to Popup.Item rendering (not Popup.Window).
    // QQuickMenu honours this attribute at qquickmenu.cpp:323; without it,
    // any future Qt Controls component (or third-party QML) that opts into
    // Popup.Window would create a host-side top-level QWindow with the
    // wrong surfaceType and trip qeglfswindow.cpp:79 ("OpenGL windows
    // cannot be mixed with others").
    QCoreApplication::setAttribute(Qt::AA_DontUseNativeMenuWindows);

    // Baseline scenegraph defaults — sRGB blending, vsync, 24/8 depth+stencil.
    // MSAA samples are chosen AFTER QGuiApplication constructs the QPA plugin
    // (needs an EGLDisplay to probe). See the probe block below.
    //
    // RenderableType: OpenGLES, not OpenGL. Etnaviv (GC7000Lite on i.MX 8M
    // Quad) only exposes a GLES profile; if Qt asks EGLFS for a desktop
    // OpenGL context it fails eglChooseConfig and falls back to a
    // different EGLConfig than every secondary surface — which is what
    // tripped "windows cannot be mixed" on every WebEngine launch.
    // Explicit major/minor + GLES profile pins the EGLConfig so both
    // the main shell window AND any internal surface Qt creates use
    // the same config.
    {
        // GLES level and framebuffer alpha come from the DeviceProfile, not
        // hardcoded L5 constants — a device whose GPU stack does GLES3 (e.g.
        // the Vivante blob) declares GLES_LEVEL=3.0, and a device whose CRTC
        // is ARGB declares SURFACE_ALPHA=1. Defaults still match the Librem 5
        // (GLES 2.0, no alpha) so an un-provisioned device is unchanged.
        const marathon::device::Profile dp  = marathon::device::profile();
        QSurfaceFormat                  fmt = QSurfaceFormat::defaultFormat();
        fmt.setRenderableType(QSurfaceFormat::OpenGLES);
        fmt.setMajorVersion(dp.gles_major);
        fmt.setMinorVersion(dp.gles_minor);
        fmt.setProfile(QSurfaceFormat::NoProfile);
        fmt.setColorSpace(QColorSpace::SRgb);
        fmt.setSamples(0);
        fmt.setSwapInterval(1);
        fmt.setDepthBufferSize(24);
        fmt.setStencilBufferSize(8);
        // Framebuffer alpha is CRTC-dependent. The Librem 5 i.MX 8M Quad LCDIF
        // DSI CRTC is XRGB8888 (no alpha): asking Qt for an EGLConfig with
        // alpha=8 returns an ARGB8888 surface whose pixel format does not
        // match the CRTC, DRM rejects every drmModePageFlip with EINVAL, and
        // the panel never updates. So we set alpha ONLY when the device
        // profile says its CRTC has an alpha channel; otherwise we leave Qt's
        // defaults (which land on the XRGB-matching EGLConfig).
        if (dp.surface_has_alpha)
            fmt.setAlphaBufferSize(8);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    // The shell's own input context (src/managers/marathoninputcontext.cpp)
    // carries the compositor's keyboard show/hide requests. QT_IM_MODULES
    // outranks the QT_IM_MODULE=none in some device configs, and it is unset
    // once the context exists so apps keep their QT_IM_MODULE=wayland.
    // After a session restart the previous shell's master can outlive its
    // process for a moment, and eglfs_kms opening the card then never gets it.
    if (qEnvironmentVariable("QT_QPA_PLATFORM").startsWith(QLatin1String("eglfs"))) {
        const int waited = marathon::device::wait_for_drm_master(5000);
        if (waited < 0)
            qCritical() << "[MarathonShell] DRM master still held after 5 s; the display will not update";
        else if (waited > 0)
            qWarning() << "[MarathonShell] waited" << waited << "ms for DRM master";
    }

    // Touch comes from Qt's evdevtouch, read on its own thread with the
    // device's parameters; 71-marathon-touch.rules hides touchscreens from
    // libinput, which eglfs reads on the GUI thread.
    const bool evdevTouch = qEnvironmentVariable("QT_QPA_PLATFORM").startsWith(QLatin1String("eglfs")) &&
        !qEnvironmentVariableIsSet("QT_QPA_GENERIC_PLUGINS");
    QStringList touchSpec;
    if (evdevTouch) {
        const marathon::device::Profile dp = marathon::device::profile();
        if (dp.touch_filter)
            touchSpec << QStringLiteral("filtered");
        // Each report is applied as it comes; compression held it for the
        // next frame's sync. Apps inherit this: the shell forwards each.
        qputenv("QML_NO_TOUCH_COMPRESSION", "1");
        if (!dp.touch_params.isEmpty())
            touchSpec << dp.touch_params;
#ifndef MARATHON_HAVE_INPUT_SUPPORT
        qputenv("QT_QPA_GENERIC_PLUGINS",
                (QStringList{QStringLiteral("evdevtouch")} + touchSpec)
                    .join(QLatin1Char(':'))
                    .toLocal8Bit());
#endif
    }

    qputenv("QT_IM_MODULES", "marathon");
    QGuiApplication app(argc, argv);
    startupMark("application");
    qunsetenv("QT_IM_MODULES");
    if (evdevTouch) {
#ifdef MARATHON_HAVE_INPUT_SUPPORT
        startTouchInput(touchSpec.join(QLatin1Char(':')));
#else
        qunsetenv("QT_QPA_GENERIC_PLUGINS");
#endif
    }

    // MSAA gate. Mesa hides etnaviv MSAA behind ETNA_DEBUG=msaa_4x since 22.3.0
    // and Vivante GC7000Lite reports GL_MAX_SAMPLES ≤ 1, so the target HW
    // can't do FBO MSAA. Default to 0 here, controlled by MARATHON_LAYER_SAMPLES.
    //
    // The previous version probed via QOffscreenSurface + QOpenGLContext, which
    // crashed the compositor in QEglFSWindow::QEglFSWindow during a later
    // surface map (the probe corrupts shared EGL state for the eglfs_kms QPA
    // underlying QtWaylandCompositor — repro: launch Notes ~12 min after boot,
    // SIGABRT at libQt6EglFSDeviceIntegration top of stack). Opt into the
    // probe with MARATHON_ENABLE_MSAA_PROBE=1 on hosts where MSAA is wanted
    // (desktop dev with virgl/llvmpipe).
    {
        bool      envOk      = false;
        const int envSamples = qEnvironmentVariableIntValue("MARATHON_LAYER_SAMPLES", &envOk);
        int       chosen     = envOk ? envSamples : marathon::device::profile().hw_msaa_samples;

        if (qEnvironmentVariableIntValue("MARATHON_ENABLE_MSAA_PROBE") != 0) {
            int               maxSamples = 0;
            bool              hasFboMsaa = false;
            QOffscreenSurface sfc;
            sfc.setFormat(QSurfaceFormat::defaultFormat());
            sfc.create();
            QOpenGLContext ctx;
            if (sfc.isValid() && ctx.create() && ctx.makeCurrent(&sfc)) {
                ctx.functions()->glGetIntegerv(GL_MAX_SAMPLES, &maxSamples);
                hasFboMsaa = ctx.hasExtension("GL_EXT_framebuffer_multisample") ||
                    ctx.format().majorVersion() >= 3;
                ctx.doneCurrent();
            }
            const int requested = envOk ? envSamples : 4;
            chosen              = (hasFboMsaa && maxSamples >= requested) ? requested : 0;
            qInfo() << "[MarathonShell] MSAA probe: GL_MAX_SAMPLES=" << maxSamples
                    << "ext=" << hasFboMsaa << "→ chosen=" << chosen;
        }

        QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
        fmt.setSamples(chosen);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    // Pin our oom_score_adj at the persistent-system end of the ladder.
    // Android uses PERSISTENT_PROC_ADJ=-800 for system_server-class
    // processes; Marathon's shell hosts the in-process compositor, 30+
    // service singletons, and DBus well-known names — losing it strands
    // every running app. It must be the last thing the OOM killer
    // considers under memory pressure.
    //
    // We write this ourselves rather than relying on a launch wrapper —
    // but only best-effort. Values below 0 require CAP_SYS_RESOURCE, and
    // we DELIBERATELY do NOT grant it via file caps on this binary.
    //
    // DO NOT `setcap cap_sys_resource`/`cap_sys_nice` on marathon-shell-bin.
    // File caps make the process AT_SECURE=1, and both glibc and musl then
    // route env lookups through secure_getenv(), which returns NULL for
    // DBUS_SESSION_BUS_ADDRESS — QDBusConnection::sessionBus() never
    // connects, org.marathonos.Shell never registers, and every shell↔app
    // IPC path dies (pill back-swipe, notifications, WiFi/BT/brightness).
    // Verified live on L5 2026-07-04: file caps present → shell OFF the
    // session bus; `setcap -r` → session bus restored, back-swipe works.
    // (An earlier comment here claimed aarch64 glibc kept
    // DBUS_SESSION_BUS_ADDRESS through AT_SECURE — that was WRONG and
    // caused the regression this replaces. The qputenv re-derive below is
    // also insufficient against AT_SECURE: secure_getenv ignores the env
    // regardless of qputenv. It only helps the no-caps respawn case.)
    //
    // The negative oom_score_adj is instead pinned by the system-level
    // marathon-shell-oom.service sidecar (runs as root, finds the shell
    // PID, writes -800) — keeping file caps OFF the binary. The best-effort
    // self-write below still lands when the process already has the cap
    // ambiently (e.g. a dev host run as root).
    {
        // Force DBUS_SESSION_BUS_ADDRESS via XDG_RUNTIME_DIR/bus regardless
        // of whether it's already in the env. On musl, file caps make us
        // AT_SECURE=1; the dynamic linker leaves the env in /proc/self/environ
        // but libdbus's call into __secure_getenv() can return NULL, leaving
        // QDBusConnection::sessionBus() permanently disconnected
        // ("Not connected to D-Bus server"). qputenv re-installs the value
        // in our process env at a fresh address libc-internal getenv resolves
        // cleanly. Without this every shell respawn after the initial greetd
        // start loses IPC to its own apps — Notes / Settings / etc see
        // "The name is not activatable" on every call.
        const QByteArray xdg = qgetenv("XDG_RUNTIME_DIR");
        if (!xdg.isEmpty())
            qputenv("DBUS_SESSION_BUS_ADDRESS", QByteArray("unix:path=") + xdg + "/bus");

        QFile oomWrite(QStringLiteral("/proc/self/oom_score_adj"));
        if (oomWrite.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            const QByteArray target("-800\n");
            if (oomWrite.write(target) != target.size()) {
                qWarning() << "[MarathonShell] oom_score_adj write short:"
                           << oomWrite.errorString();
            }
            oomWrite.close();
        }

        // Read back to confirm.
        QFile oomRead(QStringLiteral("/proc/self/oom_score_adj"));
        if (oomRead.open(QIODevice::ReadOnly)) {
            const int score = oomRead.readAll().trimmed().toInt();
            oomRead.close();
            if (score > 0) {
                qWarning() << "[MarathonShell] oom_score_adj=" << score
                           << "(expected -800). marathon-shell-oom.service"
                              " sidecar not active yet? Under memory pressure"
                              " the shell may be killed before its apps."
                              " (Do NOT 'fix' with setcap — file caps break"
                              " the D-Bus session bus.)";
            } else {
                qInfo() << "[MarathonShell] oom_score_adj=" << score << "(PERSISTENT_PROC bias)";
            }
        }
    }

    // Logging filter rules must go AFTER QGuiApplication: the QGuiApplication
    // constructor processes QT_LOGGING_RULES and Qt config-file rules,
    // which can override anything set earlier in main.
    if (debugEnabled) {
        // Order matters here: in QLoggingCategory rules the LAST matching pattern
        // wins. We start with broad enables, then disable qt.* spam, then turn the
        // qt.* warnings back on. The bare *.<level>=true *also* enables qInfo for
        // the "default" category (qInfo() / qDebug() with no qCDebug category).
        QString rules = QStringLiteral("*.debug=true\n") + QStringLiteral("*.info=true\n") +
            QStringLiteral("*.warning=true\n") + QStringLiteral("*.error=true\n") +
            QStringLiteral("qt.*.debug=false\n") + QStringLiteral("qt.*.info=false\n") +
            QStringLiteral("qt.*.warning=true\n") + QStringLiteral("qml.debug=true\n") +
            QStringLiteral("js.debug=true\n");
        if (profileMode) {
            rules += QStringLiteral("qt.scenegraph.time.*=true\n");
            rules += QStringLiteral("qt.scenegraph.time.renderloop=true\n");
        }
        QLoggingCategory::setFilterRules(rules);
    } else {
        QString rules = QStringLiteral("*.debug=false\n") + QStringLiteral("*.info=false\n") +
            QStringLiteral("*.warning=true\n") + QStringLiteral("*.error=true\n") +
            QStringLiteral("qt.qpa.*=false\n") + QStringLiteral("qt.pointer.*=false\n") +
            QStringLiteral("qt.quick.*=false\n") + QStringLiteral("qt.scenegraph.*=false\n") +
            QStringLiteral("marathon.*.info=true\n");
        if (profileMode) {
            rules += QStringLiteral("qt.scenegraph.time.*=true\n");
            rules += QStringLiteral("qt.scenegraph.time.renderloop=true\n");
        }
        QLoggingCategory::setFilterRules(rules);
    }

#ifdef Q_OS_LINUX
    // Shell main thread = SCHED_RR/2; render thread is set to RR/1 from
    // WaylandCompositor. See docs/RT_SCHEDULING.md for the full hierarchy.
    if (const int rc = marathon::rt::set_thread_priority(2); rc != 0) {
        qWarning() << "[MarathonShell] Main thread RT elevation failed:" << strerror(rc)
                   << "-- grant CAP_SYS_NICE or rtprio in /etc/security/limits.d/.";
    }
#endif

    QString logPath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + "/.marathon";
    QDir    logDir(logPath);
    if (!logDir.exists()) {
        logDir.mkpath(".");
    }

    logFile = new QFile(logPath + "/crash.log");
    if (logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        logStream = new QTextStream(logFile);
        qInstallMessageHandler(marathonMessageHandler);
        qInfo() << "Marathon Shell starting...";
        qInfo() << "Log file:" << logFile->fileName();
    } else {
        qWarning() << "Failed to open log file:" << logFile->fileName();
        delete logFile;
        logFile = nullptr;
    }
    if (debugEnabled) {
        qDebug() << "[Profiler] Logging initialized:" << timer.elapsed() << "ms";
    }

    QQuickStyle::setStyle("Basic");

    if (debugEnabled) {
        qDebug() << "Debug mode enabled via MARATHON_DEBUG";
    }

#ifdef HAVE_WAYLAND

    qmlRegisterType<NativeSurfaceItem>("MarathonOS.Shell", 1, 0, "NativeSurfaceItem");
    qmlRegisterUncreatableType<QWaylandSurface>("MarathonOS.Wayland", 1, 0, "WaylandSurface",
                                                "WaylandSurface cannot be created from QML");
    qmlRegisterUncreatableType<QWaylandXdgSurface>("MarathonOS.Wayland", 1, 0, "WaylandXdgSurface",
                                                   "WaylandXdgSurface cannot be created from QML");
    qmlRegisterUncreatableType<WaylandCompositor>("MarathonOS.Wayland", 1, 0, "WaylandCompositor",
                                                  "WaylandCompositor is created in C++");

    qRegisterMetaType<QWaylandSurface *>("QWaylandSurface*");
    qRegisterMetaType<QWaylandXdgSurface *>("QWaylandXdgSurface*");
    qRegisterMetaType<QObject *>("QObject*");

    qInfo() << "Wayland Compositor support enabled";
#else
    qInfo() << "Wayland Compositor support disabled (not available on this platform)";
#endif

    // Force QtRendering for every Text — Qt 6 documents QtTextRendering as
    // the default but Alpine's Qt6 build defaults to NativeRendering, which
    // routes font-family lookup through fontconfig and silently falls back
    // to Noto Sans (Sora lives only in the per-app QML resource, not in
    // the system fontconfig cache). Without this every Text without an
    // explicit renderType drops out of Sora — the lock clock looks right
    // (explicit Text.QtRendering) while the home grid labels don't.
    QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);

    QQmlApplicationEngine engine;

    qmlRegisterType<InputContext>("MarathonOS.Shell", 1, 0, "InputContext");
    qmlRegisterType<GestureTracker>("MarathonOS.Shell", 1, 0, "GestureTracker");
    qmlRegisterType<FileChooserModel>("MarathonOS.Shell", 1, 0, "FileChooserModel");
    qmlRegisterType<WindowTextureItem>("MarathonOS.Shell", 1, 0, "WindowTextureItem");
    qmlRegisterType<BackdropProbe>("MarathonOS.Shell", 1, 0, "BackdropProbe");

    auto *sessionStore = new Session();
    sessionStore->setParent(&app);
    qmlRegisterSingletonInstance<Session>("MarathonOS.Shell", 1, 0, "SessionStore", sessionStore);

    engine.addImageProvider("svg", new SvgImageProvider());

    auto *ctx = engine.rootContext();

    auto *screenMetrics = createObject<ScreenMetrics>(ctx, "ScreenMetricsCpp", &app);

    const marathon::device::Profile device = marathon::device::profile();
    ctx->setContextProperty(QStringLiteral("DeviceProfile"),
                            QVariantMap{{QStringLiteral("panelDither"), device.panel_dither},
                                        {QStringLiteral("panelDepth"), device.panel_depth}});
    ctx->setContextProperty(QStringLiteral("Platform"),
                            QVariantMap{{QStringLiteral("hasHardwareKeyboard"),
                                         marathon::device::has_hardware_keyboard()}});

    auto *mpris2Controller = new Mpris();
    mpris2Controller->setParent(&app);
    qmlRegisterSingletonInstance<Mpris>("MarathonOS.Shell", 1, 0, "MPRIS2Controller",
                                        mpris2Controller);
    qInfo() << "[MarathonShell]MPRIS2 media controller initialized";

    startupMark("stores");
    auto *settingsManager = new marathon::Settings();
    settingsManager->setParent(&app);
    settingsManager->load(device.screen_timeout_ms);
    qmlRegisterSingletonInstance<marathon::Settings>("MarathonOS.Shell", 1, 0, "SettingsManagerCpp",
                                                  settingsManager);

    auto *translations = new Translations({QStringLiteral("shell"), QStringLiteral("silica")}, &app);
    const auto speak = [translations, settingsManager] {
        translations->install(settingsManager->getLanguage());
        marathon::i18n::export_to_session();
    };
    speak();
    QObject::connect(settingsManager, &marathon::Settings::languageChanged, translations, speak);
    QObject::connect(translations, &Translations::installed, &engine, &QQmlEngine::retranslate);

    auto *ambienceService = new marathon::Ambience();
    ambienceService->setParent(&app);
    ambienceService->setWallpaper(settingsManager->getWallpaperPath());
    QObject::connect(settingsManager, &marathon::Settings::wallpaperPathChanged, ambienceService,
                     [settingsManager, ambienceService]() {
                         ambienceService->setWallpaper(settingsManager->getWallpaperPath());
                     });
    qmlRegisterSingletonInstance<marathon::Ambience>("MarathonOS.Shell", 1, 0, "AmbienceService",
                                                  ambienceService);
    // Keel picks phone or tablet metrics (page margins, ...) from the panel's
    // physical size; a DT that misreports it (the HackberryPi's doubled
    // width-mm) gives a phone tablet margins. The profile's true DPI wins.
    if (!qEnvironmentVariableIsSet("KEEL_SCREEN_DIAGONAL") && device.panel_dpi > 0) {
        if (const QScreen *screen = QGuiApplication::primaryScreen()) {
            const QSize px = screen->size() * screen->devicePixelRatio();
            const qreal inches = std::hypot(px.width(), px.height()) / device.panel_dpi;
            qputenv("KEEL_SCREEN_DIAGONAL", QByteArray::number(inches, 'f', 2));
        }
    }

    // Keel apps and the shell's Silica take their size from this ratio, so
    // the interface-size setting scales them with the rest of the shell.
    {
        auto update = [ambienceService, settingsManager, screenMetrics]() {
            ambienceService->setScale(screenMetrics->dpi(), settingsManager->getUserScaleFactor());
            const qreal ratio = ambienceService->getPixelRatio();
            // Keel's forwarded layer, read when its Ambience is first created:
            // the shell's Silica starts at this ratio instead of the width rule.
            if (ratio > 0) {
                qputenv("KEEL_AMBIENCE_KEYS", "/desktop/sailfish/silica/theme_pixel_ratio");
                qputenv("KEEL_SILICA_THEME_PIXEL_RATIO", QByteArray::number(ratio));
            }
        };
        update();
        QObject::connect(settingsManager, &marathon::Settings::userScaleFactorChanged, ambienceService, update);
        QObject::connect(screenMetrics, &ScreenMetrics::metricsChanged, ambienceService, update);
    }

    auto *compositorManager =
        createObject<WaylandCompositorManager>(ctx, "WaylandCompositorManager", &app);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] Compositor Manager initialized:" << timer.elapsed() << "ms";
    }
#ifdef HAVE_WAYLAND
    // Native apps follow the interface size too, from the DPI the shell scales by.
    {
        auto update = [compositorManager, settingsManager, screenMetrics, scale = device.native_scale]() {
            compositorManager->setNativeScale(
                NativeClientScale::fromDpi(screenMetrics->dpi(), settingsManager->getUserScaleFactor(),
                                           scale));
        };
        update();
        QObject::connect(settingsManager, &marathon::Settings::userScaleFactorChanged,
                         compositorManager, update);
        QObject::connect(screenMetrics, &ScreenMetrics::metricsChanged, compositorManager, update);
    }
#endif

    ctx->setContextProperty("MARATHON_DEBUG_ENABLED", debugEnabled);

    // MARATHON_LAYER_SAMPLES → QML Constants.layerSamples. Default 4 (the
    // QML design system was authored against), env override 0 on GPUs
    // without HW multisample renderbuffers (etnaviv GC7000Lite on the
    // i.MX 8M Quad). Without this gate every layer-wrapped QML item
    // tries to allocate a 4× MSAA renderbuffer, the alloc fails, Qt logs
    // "Layer requested 4 samples but multisample renderbuffers are not
    // supported" at ~100 lines/sec during animations. See memory
    // [Etnaviv MSAA trap].
    bool      samplesOk       = false;
    const int envLayerSamples = qEnvironmentVariableIntValue("MARATHON_LAYER_SAMPLES", &samplesOk);
    const int layerSamples    = samplesOk ? envLayerSamples : 4;
    ctx->setContextProperty("MARATHON_LAYER_SAMPLES", layerSamples);

    // MARATHON_GPU_HDR → QML Constants.gpuHdr. Default false. When true,
    // AppBackdropBlur (and other halo / glow primitives) requests an
    // RGBA16F ShaderEffectSource to keep gamma-precise compositing. On
    // etnaviv that allocation fails with "QSGRhiLayer: Attempted to set
    // unsupported texture format 8" — the GC7000Lite doesn't expose
    // RGBA16F as a colour-buffer attachment. Falling back to RGBA8
    // gives a slightly darker halo around bright pixels but no warnings
    // and no perf hit.
    ctx->setContextProperty("MARATHON_GPU_HDR", marathon::device::profile().gpu_hdr);

#ifdef HAVE_WAYLAND
    ctx->setContextProperty("HAVE_WAYLAND", true);
#else
    ctx->setContextProperty("HAVE_WAYLAND", false);
#endif

    // MARATHON_FPS_OVERLAY -> live on-screen FPS counter (top-right).
    // Diagnostic: shows real presented-frame rate during interaction so
    // framerate regressions on the GC7000Lite are visible without journald.
    const bool fpsOverlay = qEnvironmentVariableIntValue("MARATHON_FPS_OVERLAY") != 0;
    auto      *fpsMonitor = new FpsMonitor(&app);
    ctx->setContextProperty("fpsMonitor", fpsMonitor);
    ctx->setContextProperty("MARATHON_FPS_OVERLAY", fpsOverlay);

    auto *appModel = new Apps();
    appModel->setParent(&app);
    ctx->setContextProperty(QStringLiteral("AppModel"), appModel);
    compositorManager->setApps(appModel);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] App System initialized:" << timer.elapsed() << "ms";
    }

    createObject<MarathonInputMethodEngine>(ctx, "InputMethodEngine", &app);
    qInfo() << "Input Method Engine initialized";

    auto *remoteTextInput = new RemoteTextInput();
    remoteTextInput->setParent(&app);
    ctx->setContextProperty(QStringLiteral("RemoteTextInput"), remoteTextInput);
    auto *remoteTextInputFilter = new RemoteTextInputFilter(
        remoteTextInput,
        [compositorManager](QObject *object) -> QString {
#ifdef HAVE_WAYLAND
            return RemoteTextInputTarget::appIdOf(object, compositorManager->compositor());
#else
            Q_UNUSED(object);
            return {};
#endif
        },
        &app);
    QObject::connect(remoteTextInput, &RemoteTextInput::panelWanted, remoteTextInputFilter,
                     [=](bool show) {
                         if (!show || remoteTextInputFilter->targetsFocus())
                             emit remoteTextInput->panelRequested(show);
                     });

    auto *tasks = new Tasks();
    tasks->setParent(&app);
    qmlRegisterSingletonInstance<Tasks>("MarathonOS.Shell", 1, 0, "Tasks", tasks);
#ifdef HAVE_WAYLAND
    QObject::connect(compositorManager, &WaylandCompositorManager::compositorCreated, tasks,
                     [tasks](WaylandCompositor *wc) { connectTasks(tasks, wc); });
#endif
    auto *notificationService = new Notifications();
    notificationService->setParent(&app);
    qmlRegisterSingletonInstance<Notifications>("MarathonOS.Shell", 1, 0, "NotificationService",
                                                notificationService);
    notificationService->setDndEnabled(settingsManager->getDndEnabled());
    QObject::connect(settingsManager, &marathon::Settings::dndEnabledChanged, notificationService,
                     [=] { notificationService->setDndEnabled(settingsManager->getDndEnabled()); });
    auto *links = new Links();
    links->setParent(&app);
    qmlRegisterSingletonInstance<Links>("MarathonOS.Shell", 1, 0, "NavigationRouter", links);

    startupMark("models");
    auto *network = new Network();
    network->setParent(&app);
    qmlRegisterSingletonInstance<Network>("MarathonOS.Shell", 1, 0, "Network",
                                                    network);
    auto *power = new Power();
    power->setParent(&app);
    qmlRegisterSingletonInstance<Power>("MarathonOS.Shell", 1, 0, "Power",
                                                  power);
    auto *display = new marathon::Display();
    display->setParent(&app);
    display->start(QStringLiteral("/sys/class/backlight"), QStringLiteral("/sys/bus/iio/devices"),
                   device.brightness_floor);
    qmlRegisterSingletonInstance<marathon::Display>("MarathonOS.Shell", 1, 0, "Display", display);
    const std::pair<const char *, void (marathon::Display::*)()> displaySettings[] = {
        {"rotationLocked", &marathon::Display::rotationLockedChanged},
        {"nightLightEnabled", &marathon::Display::nightLightEnabledChanged},
        {"nightLightTemperature", &marathon::Display::nightLightTemperatureChanged},
        {"nightLightSchedule", &marathon::Display::nightLightScheduleChanged},
        {"learnedCurve", &marathon::Display::learnedCurveChanged},
    };
    for (const auto &setting : displaySettings) {
        const char   *name    = setting.first;
        const auto    changed = setting.second;
        const QString key     = QStringLiteral("display/") + QLatin1String(name);
        if (const QVariant saved = settingsManager->get(key, QVariant()); saved.isValid())
            display->setProperty(name, saved);
        // clazy cannot follow a member pointer read from the table.
        QObject::connect(display, changed, settingsManager, // clazy:exclude=connect-non-signal
                         [=] { settingsManager->set(key, display->property(name)); });
    }
    display->setAutoBrightness(settingsManager->getAutoBrightness());
    QObject::connect(settingsManager, &marathon::Settings::autoBrightnessChanged, display,
                     [=] { display->setAutoBrightness(settingsManager->getAutoBrightness()); });
    QObject::connect(display, &marathon::Display::autoBrightnessChanged, settingsManager,
                     [=] { settingsManager->setAutoBrightness(display->getAutoBrightness()); });
    QObject::connect(display, &marathon::Display::screenStateChanged, power, [power](bool on) {
        if (on)
            power->acquireWakelock(QStringLiteral("display"));
        else
            power->releaseWakelock(QStringLiteral("display"));
    });
    auto *audioManager = new marathon::Audio();
    audioManager->setParent(&app);
    qmlRegisterSingletonInstance<marathon::Audio>("MarathonOS.Shell", 1, 0, "AudioManagerCpp",
                                                  audioManager);
    auto *modem = new Modem();
    modem->setParent(&app);
    // The modem, its calls and its cell broadcasts.
    qmlRegisterSingletonInstance<Modem>("MarathonOS.Shell", 1, 0, "Modem", modem);
    modem->setDataRoamingAllowed(settingsManager->get("cellular/dataRoaming", false).toBool());
    QObject::connect(modem, &Modem::dataRoamingAllowedChanged, settingsManager, [=] {
        settingsManager->set("cellular/dataRoaming", modem->getDataRoamingAllowed());
    });
    auto *wakeTouchFilter = new WakeTouchFilter(&app);
    app.installEventFilter(wakeTouchFilter);
    QObject::connect(display, &marathon::Display::screenOnChanged, wakeTouchFilter,
                     [=] { wakeTouchFilter->setScreenOn(display->getScreenOn()); });
    auto *bluetoothManager = new Bluetooth();
    bluetoothManager->setParent(&app);
    ctx->setContextProperty("BluetoothManagerCpp", bluetoothManager);
    // The device name is what other Bluetooth devices see.
    auto applyDeviceName = [bluetoothManager, settingsManager]() {
        bluetoothManager->setAdapterAlias(settingsManager->getDeviceName());
    };
    QObject::connect(settingsManager, &marathon::Settings::deviceNameChanged, bluetoothManager,
                     applyDeviceName);
    QObject::connect(bluetoothManager, &Bluetooth::availableChanged, bluetoothManager,
                     applyDeviceName);
    startupMark("system managers");
    auto *locationManager = new Location();
    locationManager->setParent(&app);
    ctx->setContextProperty("LocationManager", locationManager);
    // Never starts location itself: with Location off there is no fix and the zone stays.
    const auto automaticTimeZone = [=] {
        if (!settingsManager->getAutomaticTimeZone() || !locationManager->getActive() ||
            locationManager->getTimestamp() <= 0)
            return;
        const QString zone = marathon::timezone::nearest(locationManager->getLatitude(),
                                                         locationManager->getLongitude());
        if (!zone.isEmpty() && zone != settingsManager->getTimeZone())
            settingsManager->setTimeZone(zone);
    };
    QObject::connect(locationManager, &Location::locationChanged, settingsManager,
                     automaticTimeZone);
    QObject::connect(settingsManager, &marathon::Settings::automaticTimeZoneChanged, settingsManager,
                     automaticTimeZone);
    auto *hapticManager = new Haptics();
    hapticManager->setParent(&app);
    qmlRegisterSingletonInstance<Haptics>("MarathonOS.Shell", 1, 0, "HapticManager", hapticManager);
    hapticManager->setEnabled(settingsManager->getVibrationEnabled());
    QObject::connect(settingsManager, &marathon::Settings::vibrationEnabledChanged, hapticManager,
                     [hapticManager, settingsManager] {
                         hapticManager->setEnabled(settingsManager->getVibrationEnabled());
                     });
    auto *ngf = new marathon::Ngf();
    ngf->setParent(&app);
    QObject::connect(ngf, &marathon::Ngf::vibrate, hapticManager, [hapticManager](const QList<int> &pattern) {
        hapticManager->vibratePattern(QVariantList(pattern.begin(), pattern.end()));
    });
    QObject::connect(ngf, &marathon::Ngf::stopVibration, hapticManager, &Haptics::cancelVibration);
    auto *clipboard = new Clipboard();
    clipboard->setParent(&app);
    ctx->setContextProperty("ClipboardManagerCpp", clipboard);
    auto *alarmManager = new Alarms();
    alarmManager->setParent(&app);
    ctx->setContextProperty("AlarmManagerCpp", alarmManager);
    QObject::connect(alarmManager, &Alarms::nextAlarmScheduled, power,
                     [power](qint64 at) { power->setWakeTimer(QStringLiteral("alarm"), at); });
    QObject::connect(alarmManager, &Alarms::dataChanged, settingsManager,
                     [=] { settingsManager->set("alarms/data", alarmManager->getData()); });
    // Its timer stands still while suspended; this runs before anything
    // below asks whether an alarm rings.
    QObject::connect(power, &Power::resumedFromSuspend, alarmManager, &Alarms::checkAlarms);
    alarmManager->setData(settingsManager->get("alarms/data", "[]").toString());
    auto *flashlightManager = new Flashlight();
    flashlightManager->setParent(&app);
    ctx->setContextProperty("FlashlightManagerCpp", flashlightManager);
    auto *security = new Security();
    security->setParent(&app);
    qmlRegisterSingletonInstance<Security>("MarathonOS.Shell", 1, 0, "Security",
                                                  security);

    startupMark("sensors, location, security");
    {
        QScreen    *screen = QGuiApplication::primaryScreen();
        const qreal dpi    = ScreenMetrics::computeDpi(screen);
        tasks->setDevice({
            {QStringLiteral("thumbnails"), QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
                                               QStringLiteral("/marathon/thumbnails")},
            {QStringLiteral("dpi"), dpi > 0 ? dpi : 160.0},
            {QStringLiteral("screenWidth"), screen ? screen->geometry().width() : 0},
            {QStringLiteral("screenHeight"), screen ? screen->geometry().height() : 0},
        });
    }
    tasks->setUserScale(settingsManager->getUserScaleFactor());
    QObject::connect(settingsManager, &marathon::Settings::userScaleFactorChanged, tasks,
                     [=] { tasks->setUserScale(settingsManager->getUserScaleFactor()); });
    auto *search = new Search();
    search->setParent(&app);
    ctx->setContextProperty("UnifiedSearchService", search);

    const QByteArray autoLaunchRaw = qgetenv("MARATHON_AUTO_LAUNCH_APP_ID").trimmed();
    if (!autoLaunchRaw.isEmpty()) {
        const QString autoAppId = QString::fromLocal8Bit(autoLaunchRaw);
        QTimer::singleShot(3000, tasks, [tasks, autoAppId]() {
            qWarning() << "[MarathonShell] Auto-launching app:" << autoAppId;
            tasks->launchApp(autoAppId);
        });
    }

    // Session stop (greetd's SIGTERM, a VT hangup, systemd stopping the
    // scope): the apps close while the compositor still serves them.
    {
        static int termPipe[2] = {-1, -1};
        if (::pipe2(termPipe, O_CLOEXEC | O_NONBLOCK) == 0) {
            struct sigaction sa {};
            sa.sa_handler = [](int) {
                const int  savedErrno = errno;
                const char b          = 1;
                (void)::write(termPipe[1], &b, 1);
                errno = savedErrno;
            };
            sigemptyset(&sa.sa_mask);
            sa.sa_flags = SA_RESTART;
            for (const int sig : {SIGTERM, SIGINT, SIGHUP})
                ::sigaction(sig, &sa, nullptr);
            auto *sn = new QSocketNotifier(termPipe[0], QSocketNotifier::Read, &app);
            QObject::connect(sn, &QSocketNotifier::activated, tasks,
                             [tasks]() {
                                 char drain[16];
                                 (void)::read(termPipe[0], drain, sizeof(drain));
                                 qInfo() << "[MarathonShell] session stop: closing apps";
                                 tasks->stopAllApps(3000);
                             });
            // Skip Qt teardown: the next shell waits on our exit for DRM master.
            QObject::connect(tasks, &Tasks::allAppsStopped,
                             settingsManager, [settingsManager]() {
                                 settingsManager->sync();
                                 qInfo() << "[MarathonShell] session stop: apps closed, exiting";
                                 std::fflush(nullptr);
                                 ::_exit(0);
                             });
        }
    }

    // Doze, the screen off: background apps freeze at once (the foreground
    // one stays thawed for an instant wake) and the Wi-Fi chip idles while
    // its association, and push, stay up.
    const bool wifiPowerSave = device.wifi_power_save;
    QObject::connect(display, &marathon::Display::screenOnChanged, tasks,
                     [=, debounceMs = -1]() mutable {
                         const bool on = display->getScreenOn();
                         if (!on) {
                             debounceMs = tasks->idleFreezeDebounceMs();
                             tasks->setIdleFreezeDebounceMs(0);
                         } else if (debounceMs >= 0) {
                             tasks->setIdleFreezeDebounceMs(debounceMs);
                             debounceMs = -1;
                         }
                         if (wifiPowerSave)
                             network->setWifiPowerSave(!on);
                     });

    // Proximity reads only during voice calls.
    QObject::connect(power, &Power::hasActiveCallsChanged, display,
                     [=] { display->setProximityWanted(power->getHasActiveCalls()); });

    // Resume-from-suspend bridge. External suspends (logind IdleAction,
    // lid switch, RTC alarm — anything not going through
    // the power key or the idle timer) never tell the shell the screen
    // went off. m_screenOn stays stale TRUE across the sleep; on the
    // power-key wake the policy then reads screenOn=true and chooses
    // LockAndTurnScreenOff → bl_power=4 → backlight stays off, even
    // though the shell is fully alive (touch works, journal moves).
    // forceScreenOn() unconditionally re-issues setScreenState(true)
    // (re-writes bl_power AND brightness) and always emits
    // screenOnChanged so dimState.restore + idleScreenTimer.restart
    // run on the resume edge — not deferred to a second power press.
    //
    // If anything triggered S3 while Marathon-Doze was active (manual
    // `systemctl suspend`, critical-battery handler, scheduled wake),
    // bring us cleanly out of Doze on resume — otherwise m_dozing
    // stays stuck TRUE and the next power-key press would call
    // exitDoze on an already-unblanked screen. exitDoze is idempotent
    // so this is a no-op when we weren't dozing.
    //
    // A wake-up armed for background work lands in Doze instead: the
    // tasks run with the screen off, as they would have in Doze. An alarm
    // ringing by then (checkAlarms runs first) keeps the screen on.
    QObject::connect(power, &Power::resumedFromSuspend, display,
                     [display, alarmManager](bool backgroundWake) {
                         if (backgroundWake && !alarmManager->getHasActiveAlarm())
                             display->turnScreenOff(QStringLiteral("background-wake (doze)"));
                         else
                             display->forceScreenOn();
                     });
    QObject::connect(alarmManager, &Alarms::alarmTriggered, display,
                     &marathon::Display::turnScreenOn);

    // logind has HandlePowerKey=ignore (50-marathon.conf): the shell owns
    // the power button, and Power reads it from /dev/input, since Qt routes
    // KEY_POWER to whichever window has focus, often an app's.
    // Full CPU clock while the user interacts; the power key counts, since
    // waking the display is the slowest thing a press does.
    app.installEventFilter(new InputBoost(&app));
    QObject::connect(power, &Power::powerKeyPressed, &app, [] { marathon::boost::input(); });
    if (device.wake_on_key) {
        app.installEventFilter(new WakeOnKeyFilter([display]() { return !display->getScreenOn(); },
                                                   [display]() { display->turnScreenOn(); }, &app));
    }
    QObject::connect(alarmManager, &Alarms::ringing, audioManager,
                     [=](bool sound, bool vibrate) {
                         power->acquireWakelock(QStringLiteral("alarm_ringing"));
                         if (sound)
                             audioManager->playAlarmSound();
                         if (vibrate)
                             hapticManager->vibratePattern({500, 500});
                     });
    QObject::connect(alarmManager, &Alarms::silenced, audioManager, [=] {
        audioManager->stopAlarmSound();
        hapticManager->cancelVibration();
        power->releaseWakelock(QStringLiteral("alarm_ringing"));
    });
    auto *screenshotService = createObject<ScreenshotServiceCpp>(
        ctx, "ScreenshotService", audioManager, hapticManager, notificationService, &app);

    // SIGUSR1 → live screenshot to $MARATHON_SCREENSHOT_PATH (default
    // /tmp/marathon-shot.png). Unlike --screenshot-after which quits
    // after one capture, this lets a driver loop:
    //   kill -USR1 $(pgrep marathon-shell-bin)
    //   scp .../marathon-shot.png .
    //   marathon-touchctl tap …  # advance OOBE / app
    //   kill -USR1 …             # capture next page
    // without restarting the shell (which would reset OOBE state).
    {
        static int sigPipe[2] = {-1, -1};
        if (::pipe2(sigPipe, O_CLOEXEC | O_NONBLOCK) == 0) {
            struct sigaction sa;
            std::memset(&sa, 0, sizeof(sa));
            sa.sa_handler = [](int) {
                const char b = '1';
                ::write(sigPipe[1], &b, 1);
            };
            sigemptyset(&sa.sa_mask);
            ::sigaction(SIGUSR1, &sa, nullptr);
            auto *sn = new QSocketNotifier(sigPipe[0], QSocketNotifier::Read, &app);
            QObject::connect(sn, &QSocketNotifier::activated, &app, [screenshotService]() {
                char drain[16];
                ::read(sigPipe[0], drain, sizeof(drain));
                const QString path =
                    qEnvironmentVariable("MARATHON_SCREENSHOT_PATH", "/tmp/marathon-shot.png");
                const bool ok = screenshotService->saveScreenshotTo(path);
                qInfo() << "[Screenshot] SIGUSR1 →" << path << (ok ? "OK" : "FAIL");
            });
            qInfo() << "[Screenshot] SIGUSR1 handler armed (default path /tmp/marathon-shot.png)";
        }
    }
    auto *uiStore = new Ui();
    uiStore->setParent(&app);
    qmlRegisterSingletonInstance<Ui>("MarathonOS.Shell", 1, 0, "UIStore", uiStore);
    auto *pilot = new marathon::PilotClient();
    pilot->setParent(&app);
    qmlRegisterSingletonInstance<marathon::PilotClient>("MarathonOS.Shell", 1, 0, "PilotClient",
                                                        pilot);
    auto *weather = new marathon::WeatherClient();
    weather->setParent(&app);
    qmlRegisterSingletonInstance<marathon::WeatherClient>("MarathonOS.Shell", 1, 0, "WeatherClient",
                                                          weather);

    createObject<CursorManager>(ctx, "CursorManager", &app);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] Hardware Managers initialized:" << timer.elapsed() << "ms";
    }

    QObject::connect(audioManager, &marathon::Audio::isPlayingChanged, power,
                     [power, audioManager]() {
                         if (audioManager->getIsPlaying()) {
                             power->acquireWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback started - acquired wakelock";
                         } else {
                             power->releaseWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback stopped - released wakelock";
                         }
                     });
    qInfo() << "[MarathonShell] Audio playback wakelock integration enabled";

    qInfo() << "[MarathonShell] Security Manager initialized (PAM + fprintd)";

    startupMark("policies and stores");
    auto *dictionary = new marathon::Dictionary();
    dictionary->setParent(&app);
    qmlRegisterSingletonInstance<marathon::Dictionary>("MarathonOS.Shell", 1, 0, "Dictionary",
                                                       dictionary);
    auto *domainSuggestions = new marathon::DomainSuggestions();
    domainSuggestions->setParent(&app);
    qmlRegisterSingletonInstance<marathon::DomainSuggestions>("MarathonOS.Shell", 1, 0,
                                                              "DomainSuggestions", domainSuggestions);
    auto *layouts = new KeyboardLayouts();
    layouts->setParent(&app);
    QObject::connect(layouts, &KeyboardLayouts::languageChanged, dictionary,
                     [=](const QString &language, const QString &words) {
                         dictionary->setLanguage(words);
                         settingsManager->setKeyboardLanguage(language);
                     });
    QObject::connect(settingsManager, &marathon::Settings::keyboardLanguageChanged, layouts, [=] {
        if (settingsManager->getKeyboardLanguage() != layouts->getCurrentLanguage())
            layouts->loadLanguage(settingsManager->getKeyboardLanguage());
    });
    layouts->loadLanguage(settingsManager->getKeyboardLanguage());
    startupMark("keyboard engine");
    qmlRegisterSingletonInstance<KeyboardLayouts>("MarathonOS.Shell", 1, 0, "LanguageManager", layouts);

    qInfo() << "[MarathonShell] Initializing Marathon Service Bus (D-Bus)...";
    QDBusConnection           bus              = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCritical() << "[MarathonShell] Failed to connect to D-Bus session bus!";
    } else {
        qInfo() << "[MarathonShell] Connected to D-Bus session bus";

        const auto pushFallback = [settingsManager] {
            marathon::push::set_fallback_notifications(settingsManager->getUnifiedPushFallbackEnabled());
        };
        pushFallback();
        QObject::connect(settingsManager, &marathon::Settings::unifiedPushFallbackEnabledChanged,
                         settingsManager, pushFallback);
        marathon::push::serve();

        auto *share = new Share();
        share->setParent(&app);
        ctx->setContextProperty("ShareService", share);
        QObject::connect(share, &Share::copyRequested, &app,
                         [](const QString &text) { QGuiApplication::clipboard()->setText(text); });

        qInfo() << "[MarathonShell] Service bus ready (6 services active)";
    }
    if (debugEnabled) {
        qDebug() << "[Profiler] DBus Services initialized:" << timer.elapsed() << "ms";
    }

    auto *permissionManager = new marathon::Permissions();
    permissionManager->setParent(&app);
    qmlRegisterSingletonInstance<marathon::Permissions>("MarathonOS.Shell", 1, 0,
                                                        "PermissionManager", permissionManager);


    auto *contacts           = new Contacts();
    contacts->setParent(&app);
    ctx->setContextProperty("ContactsManager", contacts);
    auto *telephonyd         = new Telephonyd();
    telephonyd->setParent(&app);
    auto *updateService = new marathon::Updates();
    updateService->setParent(&app);
    QObject::connect(updateService, &marathon::Updates::rebootRequested, power, &Power::restart);
    QObject::connect(updateService, &marathon::Updates::settingsRequested, links, [=] {
        links->navigateToDeepLink(QStringLiteral("settings"), QStringLiteral("updates"), {});
    });
    const auto startupPin = [updateService, security]() {
        updateService->setStartupPin(security->getDataEncryption() == u"pin");
    };
    startupPin();
    QObject::connect(security, &Security::dataEncryptionChanged, updateService, startupPin);
    const auto reconsider = [=] {
        updateService->reconsider(!display->getScreenOn() && !power->getHasActiveCalls() &&
                                  !alarmManager->getHasActiveAlarm());
    };
    QObject::connect(power, &Power::hasActiveCallsChanged, updateService, reconsider);
    QObject::connect(display, &marathon::Display::screenOnChanged, updateService, reconsider);
    QObject::connect(power, &Power::isPluggedInChanged, updateService, reconsider);
    QObject::connect(power, &Power::resumedFromSuspend, updateService, reconsider);
    QObject::connect(network, &Network::wifiConnectedChanged, updateService, reconsider);
    QObject::connect(alarmManager, &Alarms::activeAlarmsChanged, updateService,
                     reconsider);
    reconsider();
    // A suspended device wakes for the restart window, as for an alarm.
    QObject::connect(updateService, &marathon::Updates::restartWindowChanged, power,
                     [power](qint64 at) { power->setWakeTimer(QStringLiteral("update-restart"), at); });
    ctx->setContextProperty("Telephonyd", telephonyd);
    // A message notification's Reply goes to its sender.
    QObject::connect(notificationService, &Notifications::replied, telephonyd,
                         [=](int id, const QString &text) {
                             const QVariantMap n  = notificationService->getNotification(int(id));
                             const QString     to = n.value(QStringLiteral("replyTarget")).toString();
                             if (text.trimmed().isEmpty() || to.isEmpty() ||
                                 n.value(QStringLiteral("appId")).toString() != QLatin1String("messages"))
                                 return;
                             telephonyd->sendMessage(to, text);
                             notificationService->markAsRead(int(id));
                         });


    // PSI some-avg10: High (≥ 20%) sends apps a low-memory hint, Critical
    // (≥ 40%) kills the longest-frozen app. systemd-oomd on the slice is the
    // fallback.
    auto *pressure = new marathon::MemoryPressure();
    pressure->setParent(&app);
    QObject::connect(pressure, &marathon::MemoryPressure::high, tasks, &Tasks::broadcastLowMemory);
    QObject::connect(pressure, &marathon::MemoryPressure::critical, tasks,
                     [tasks] { tasks->killOldestFrozenApp(); });

    {
        QObject::connect(tasks, &Tasks::openAppRequested, uiStore,
                         [uiStore](const QString &appId, const QString &name, const QString &icon, bool restore) {
                             if (restore)
                                 uiStore->restoreApp(appId, name, icon);
                             else
                                 uiStore->openApp(appId, name, icon);
                         });
        // Settled first: the switcher closes and the next app opens in one turn.
        auto *settle = new QTimer(&app);
        settle->setSingleShot(true);
        settle->setInterval(0);
        QObject::connect(settle, &QTimer::timeout, tasks, [=] {
            tasks->setShellState(uiStore->getAppWindowOpen(), uiStore->getCurrentAppId(), sessionStore->getIsLocked(),
                                 uiStore->getQuickSettingsOpen());
        });
        QObject::connect(uiStore, &Ui::appWindowOpenChanged, settle, qOverload<>(&QTimer::start));
        QObject::connect(uiStore, &Ui::currentAppIdChanged, settle, qOverload<>(&QTimer::start));
        QObject::connect(uiStore, &Ui::quickSettingsOpenChanged, settle, qOverload<>(&QTimer::start));
        QObject::connect(sessionStore, &Session::isLockedChanged, settle, qOverload<>(&QTimer::start));
        settle->start();
#ifdef HAVE_WAYLAND
        QObject::connect(tasks, &Tasks::foregroundAppIdChanged, &app, [=] {
            WaylandCompositor *compositor = compositorManager->compositor();
            if (tasks->getForegroundAppId().isEmpty() && compositor)
                compositor->releaseForeignKeyboard();
        });
#endif
        auto *fileChooser = new FileChooser();
        fileChooser->setParent(&app);
        ctx->setContextProperty("FileChooserPortal", fileChooser);
        marathon::ipc::own_name();
    }

    QObject::connect(modem, &Modem::callEnded, telephonyd, &Telephonyd::logCall);
    qInfo() << "[MarathonShell] Call history wired to telephony";


    engine.addImportPath("qrc:/");
    engine.addImportPath(QStringLiteral("/usr/lib/qt6/qml"));
    engine.addImportPath(QStringLiteral("/usr/local/lib/qt6/qml"));
    engine.addImportPath(QCoreApplication::applicationDirPath() + "/..");

    const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));

    const auto devices = QInputDevice::devices();
#if !defined(QT_NO_INFO_OUTPUT)
    qInfo() << "[MarathonShell] Detected Input Devices:";
    for (const QInputDevice *device : devices) {
        qInfo() << "  -" << device->name() << "Type:" << device->type()
                << "ID:" << device->systemId() << "Seat:" << device->seatName();
    }
#else
    Q_UNUSED(devices)
#endif

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML";
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    startupMark("services");
    engine.load(url);
    startupMark("qml loaded");

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }
    const QList<QObject *> roots = engine.rootObjects();
    for (QObject *root : roots) {
        if (auto *win = qobject_cast<QQuickWindow *>(root)) {
            QObject::connect(
                win, &QQuickWindow::frameSwapped, win,
                [] {
                    startupMark("first frame");
                    // marathon-boot-health.service waits for this to bless the boot.
                    const QString runtimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR");
                    if (!runtimeDir.isEmpty()) {
                        QFile ready(runtimeDir + QStringLiteral("/marathon-shell-ready"));
                        if (!ready.open(QIODevice::WriteOnly))
                            qWarning() << "[MarathonShell] cannot mark first frame:"
                                       << ready.errorString();
                    }
                },
                Qt::SingleShotConnection);
            break;
        }
    }

    // MARATHON_TOUCH_RESAMPLE=0 turns it off.
    if (evdevTouch && !device.touch_filter &&
        qEnvironmentVariable("MARATHON_TOUCH_RESAMPLE") != QLatin1String("0")) {
        const auto rootObjects = engine.rootObjects();
        for (QObject *root : rootObjects) {
            if (auto *win = qobject_cast<QQuickWindow *>(root)) {
                auto *resampler = new TouchResampler(win, win->contentItem());
#ifdef HAVE_WAYLAND
                resampler->setVblankClock([compositorManager]() -> qint64 {
                    WaylandCompositor *compositor = compositorManager->compositor();
                    return compositor ? compositor->frameLatchUs() : -1;
                });
#else
                Q_UNUSED(resampler);
#endif
            }
        }
    }

    // The shell's single QQuickWindow is the root object (Main.qml Window).
    // Wire the FPS monitor to its frame-swap signal now that it exists.
    if (fpsOverlay) {
        const auto rootObjects = engine.rootObjects();
        for (QObject *root : rootObjects) {
            if (auto *win = qobject_cast<QQuickWindow *>(root)) {
                fpsMonitor->attach(win);
                qInfo() << "[MarathonShell] FPS overlay enabled";
                break;
            }
        }
    }

    QTimer::singleShot(
        0, &app, [&app, settingsManager, appModel]() {
            const QStringList searchPaths = {
                "/usr/share/applications", "/usr/local/share/applications",
                QDir::homePath() + "/.local/share/applications",
                "/var/lib/flatpak/exports/share/applications",
                QDir::homePath() + "/.local/share/flatpak/exports/share/applications"};

            const bool filterMobile = settingsManager->getFilterMobileFriendlyApps();

#ifdef HAVE_QT_CONCURRENT
            auto *watcher = new QFutureWatcher<QVariantList>(&app);
            QObject::connect(watcher, &QFutureWatcher<QVariantList>::finished, &app,
                             [watcher, appModel]() {
                                 const QVariantList nativeApps = watcher->result();
                                 appModel->addApps(nativeApps);
                                 watcher->deleteLater();
                             });

            QFuture<QVariantList> future = QtConcurrent::run(
                [searchPaths, filterMobile]() { return marathon::desktop::scan(searchPaths, filterMobile); });
            watcher->setFuture(future);
#else
        const QVariantList nativeApps = marathon::desktop::scan(searchPaths, filterMobile);
        appModel->addApps(nativeApps);
#endif

            // Rescans parse every entry on the pool (Waydroid rewrites its
            // entries while it runs) and apply the newest result here.
            const auto scanDesktopApps =
                [appPtr = &app](const std::shared_ptr<int> &scanGeneration, const QStringList &paths,
                                bool filterMobile,
                                const std::function<void(const QVariantList &)> &apply) {
                    const int generation = ++*scanGeneration;
                    auto     *watcher    = new QFutureWatcher<QVariantList>(appPtr);
                    QObject::connect(watcher, &QFutureWatcher<QVariantList>::finished, appPtr,
                                     [watcher, apply, generation, scanGeneration]() {
                                         if (generation == *scanGeneration)
                                             apply(watcher->result());
                                         watcher->deleteLater();
                                     });
                    watcher->setFuture(QtConcurrent::run(
                        [paths, filterMobile]() { return marathon::desktop::scan(paths, filterMobile); }));
                };
            const auto replaceApps = [appModel](const QVariantList &apps, const QStringList &types) {
                QSet<QString> seen;
                for (const QVariant &v : apps)
                    seen.insert(v.toMap().value(QStringLiteral("id")).toString());
                for (const QString &type : types) {
                    const QStringList existing = appModel->appIdsByType(type);
                    for (const QString &id : existing) {
                        if (!seen.contains(id))
                            appModel->removeApp(id);
                    }
                }
                appModel->addApps(apps);
            };
            const auto rescanDesktopApps = [scanDesktopApps, replaceApps, settingsManager,
                                            searchPaths, generation = std::make_shared<int>(0)]() {
                scanDesktopApps(generation, searchPaths, settingsManager->getFilterMobileFriendlyApps(),
                                [replaceApps](const QVariantList &apps) {
                                    replaceApps(apps, {QStringLiteral("native"),
                                                       QStringLiteral("flatpak")});
                                });
            };
            // "Hide desktop apps" applies as soon as it is switched.
            QObject::connect(settingsManager, &marathon::Settings::filterMobileFriendlyAppsChanged,
                             &app, rescanDesktopApps);

            // Waydroid writes and removes its apps' entries here while it runs.
            const QString userApps =
                QDir::homePath() + QStringLiteral("/.local/share/applications");
            QDir().mkpath(userApps);
            auto *userAppsWatcher  = new QFileSystemWatcher({userApps}, &app);
            auto *userAppsDebounce = new QTimer(&app);
            userAppsDebounce->setSingleShot(true);
            userAppsDebounce->setInterval(500);
            QObject::connect(userAppsWatcher, &QFileSystemWatcher::directoryChanged,
                             userAppsDebounce, qOverload<>(&QTimer::start));
            QObject::connect(userAppsDebounce, &QTimer::timeout, &app, rescanDesktopApps);

            // The Store writes which Flathub apps fit a phone here (replaced
            // whole, so the directory is watched).
            const QString storeCache = QFileInfo(marathon::desktop::phone_apps_path()).absolutePath();
            QDir().mkpath(storeCache);
            auto *storeCacheWatcher = new QFileSystemWatcher({storeCache}, &app);
            QObject::connect(storeCacheWatcher, &QFileSystemWatcher::directoryChanged,
                             userAppsDebounce,
                             [userAppsDebounce,
                              seen = QFileInfo(marathon::desktop::phone_apps_path()).lastModified()]() mutable {
                                 const QDateTime now =
                                     QFileInfo(marathon::desktop::phone_apps_path()).lastModified();
                                 if (now != seen) {
                                     seen = now;
                                     userAppsDebounce->start();
                                 }
                             });

            // The user directory only appears with the first flatpak install,
            // which is exactly the change this watch exists to catch, so
            // create it rather than skip it.
            const QString userFlatpakApps = QDir::homePath() +
                QStringLiteral("/.local/share/flatpak/exports/share/applications");
            QDir().mkpath(userFlatpakApps);
            QStringList flatpakDirs{userFlatpakApps};
            if (QDir(QStringLiteral("/var/lib/flatpak/exports/share/applications")).exists())
                flatpakDirs.append(QStringLiteral("/var/lib/flatpak/exports/share/applications"));
            if (!flatpakDirs.isEmpty()) {
                auto *flatpakWatcher = new QFileSystemWatcher(&app);
                flatpakWatcher->addPaths(flatpakDirs);

                auto *debounce = new QTimer(&app);
                debounce->setSingleShot(true);
                debounce->setInterval(500);

                QObject::connect(flatpakWatcher, &QFileSystemWatcher::directoryChanged, debounce,
                                 qOverload<>(&QTimer::start));

                QObject::connect(debounce, &QTimer::timeout, &app,
                                 [scanDesktopApps, replaceApps, flatpakDirs, settingsManager,
                                  generation = std::make_shared<int>(0)]() {
                                     scanDesktopApps(generation, flatpakDirs,
                                                     settingsManager->getFilterMobileFriendlyApps(),
                                                     [replaceApps](const QVariantList &apps) {
                                                         replaceApps(apps, {QStringLiteral("flatpak")});
                                                     });
                                 });
            }
        });

    qDebug() << "Marathon OS Shell started";
    return QGuiApplication::exec();
}
