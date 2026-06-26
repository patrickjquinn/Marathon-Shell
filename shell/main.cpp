#include <QGuiApplication>
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
#include <QDBusMetaType>
#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QSet>
#include <QTimer>
#include <QSurfaceFormat>
#include <QColorSpace>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>

#include "util/rtprio.h"
#include <cstring>

#include <QSocketNotifier>
#include <csignal>
#include <unistd.h>
#include <fcntl.h>

#include "src/components/desktopfileparser.h"
#include "src/components/crashhandler.h"
#include "src/models/appmodel.h"
#include "src/models/taskmodel.h"
#include "src/managers/alarmmanagercpp.h"
#include "src/services/applaunchservice.h"
#include "src/services/applifecyclemanager.h"
#include "src/services/backgroundtaskobserver.h"
#include "src/services/memorypressuremonitor.h"
#include "src/models/notificationmodel.h"
#include "src/services/notificationhandlercpp.h"
#include "src/services/notificationservicecpp.h"
#include "src/services/unifiedpushdistributor.h"
#include "src/services/marathonntfyclient.h"
#include "src/services/carrierprovisioning.h"
#include "src/services/flatpakmanager.h"
#include "src/services/motiondaemon.h"
#include "src/managers/networkmanagercpp.h"
#include "src/managers/powermanagercpp.h"
#include "src/controllers/powerpolicycontroller.h"
#include "src/managers/displaymanagercpp.h"
#include "src/managers/powerkeylistener.h"
#include "src/controllers/displaypolicycontroller.h"
#include "src/services/powerbatteryhandlercpp.h"
#include "src/managers/audiomanagercpp.h"
#include "src/managers/modemmanagercpp.h"
#include "src/managers/sensormanagercpp.h"
#include "src/managers/settingsmanager.h"
#include "src/managers/bluetoothmanager.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"
#include "marathonappinstaller.h"
#include "src/marathonpermissionmanager.h"
#include "src/services/marathonappstoreservice.h"
#include "src/services/updateservice.h"
#include "contactsmanager.h"
#include "telephonyservice.h"
#include "callhistorymanager.h"
#include "smsservice.h"
#include "mmsmanager.h"
#include "davsyncengine.h"
#include "davcalendarstore.h"
#include "medialibrarymanager.h"
#include "musiclibrarymanager.h"
#include "src/wayland/waylandcompositormanager.h"
#include "src/managers/marathoninputmethodengine.h"
#include "src/managers/rtscheduler.h"
#include "src/managers/cursormanager.h"
#include "src/components/lunasvgimageprovider.h"

#include "src/managers/mpris2controller.h"
#include "src/managers/rotationmanager.h"
#include "src/managers/locationmanager.h"
#include "src/managers/clipboardmanagercpp.h"
#include "src/managers/hapticmanager.h"
#include "src/managers/flashlightmanagercpp.h"
#include "src/controllers/audioroutingmanager.h"
#include "src/controllers/audiopolicycontroller.h"
#include "src/managers/securitymanager.h"
#include "src/managers/screenmetrics.h"
#include "src/managers/platformcpp.h"
#include "src/services/navigationroutercpp.h"
#include "src/services/statusbariconservicecpp.h"
#include "src/services/statemanagercpp.h"
#include "src/services/unifiedsearchservicecpp.h"
#include "src/services/telephonyintegrationcpp.h"
#include "src/services/screenshotservicecpp.h"
#include "src/services/sessionstore.h"
#include "src/services/systemstatusstore.h"
#include "src/services/systemcontrolstore.h"
#include "src/services/uistore.h"
#include "src/services/appstore.h"
#include "src/services/wallpaperstore.h"
#include "src/services/router.h"
#include "src/services/surfaceregistry.h"
#include "src/services/languagemanager.h"
#include "src/services/dictionary.h"
#include "src/services/autocorrect.h"
#include "src/services/emojipredictor.h"
#include "src/services/phrasepredictor.h"
#include "src/services/inputcontext.h"
#include "qml/keyboard/Data/WordEngine.h"
#include "src/dbus/freedesktopnotifications.h"
#include "src/dbus/notificationdatabase.h"
#include "src/ipc/shellipcserver.h"
#include <QDBusConnection>

#ifdef HAVE_WAYLAND
#include "src/wayland/waylandcompositor.h"
#include <QWaylandSurface>
#include <QWaylandXdgShell>
#endif

template <typename T, typename... Args>
static T *createObject(QQmlContext *ctx, const char *qmlName, Args &&...args) {
    static_assert(std::is_base_of_v<QObject, T>, "T must inherit QObject");

    T *obj = new T(std::forward<Args>(args)...);
    ctx->setContextProperty(qmlName, obj);
    return obj;
}

static QFile       *logFile   = nullptr;
static QTextStream *logStream = nullptr;
static QMutex       logMutex;
static bool         g_debugEnabled = false;
static void         marathonMessageHandler(QtMsgType type, const QMessageLogContext &context,
                                           const QString &msg) {

    QMutexLocker locker(&logMutex);

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

#include "src/components/mpris_types.h"

int main(int argc, char *argv[]) {

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");

    // Curved-edge AA via geometry where FBO MSAA is unavailable. Etnaviv
    // (GC7000Lite) hides MSAA renderbuffers — without this Shape strokes,
    // squircle hairlines, and ShapePath outlines render aliased. Cost is
    // a few extra triangles per Shape; the scenegraph already supports
    // this code path. See doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph-renderer.html.
    if (!qEnvironmentVariableIsSet("QSG_ANTIALIASING_METHOD"))
        qputenv("QSG_ANTIALIASING_METHOD", "vertex");

    registerMprisTypes();

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
        QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
        fmt.setRenderableType(QSurfaceFormat::OpenGLES);
        fmt.setMajorVersion(2);
        fmt.setMinorVersion(0);
        fmt.setProfile(QSurfaceFormat::NoProfile);
        fmt.setColorSpace(QColorSpace::SRgb);
        fmt.setSamples(0);
        fmt.setSwapInterval(1);
        fmt.setRedBufferSize(8);
        fmt.setGreenBufferSize(8);
        fmt.setBlueBufferSize(8);
        fmt.setAlphaBufferSize(8);
        fmt.setDepthBufferSize(24);
        fmt.setStencilBufferSize(8);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    QGuiApplication app(argc, argv);

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
        int       chosen     = envOk ? envSamples : 0;

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
    // We write this ourselves rather than relying on a launch wrapper.
    // Values below 0 require CAP_SYS_RESOURCE, granted via
    //   setcap cap_sys_resource+ep /usr/bin/marathon-shell-bin
    // in the marathon-shell APKBUILD. The systemd-run --user path
    // can't do this (user@.service has no CAP_SYS_RESOURCE) and the
    // systemd-run --system path requires greetd-as-root which breaks
    // PAM. setcap is the surgical fix.
    //
    // AT_SECURE concern: file caps make the binary AT_SECURE, which
    // makes glibc drop "unsafe" env vars. DBUS_SESSION_BUS_ADDRESS is
    // NOT in glibc's secure_getenv blocklist on aarch64 — verified
    // against glibc 2.40 setjmp/secure_getenv.c — so DBus IPC keeps
    // working without manual re-derivation. The defensive re-derive
    // below is belt-and-braces in case a future glibc tightens the
    // list.
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
                           << "(expected -800). setcap cap_sys_resource missing"
                              " on marathon-shell-bin? Under memory pressure"
                              " the shell may be killed before its apps.";
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

    CrashHandler *crashHandler = CrashHandler::instance();
    crashHandler->install();
    crashHandler->setCrashCallback([](const QString &msg) {
        qCritical() << "[Marathon] App crash detected:" << msg;
        qCritical() << "[Marathon] Crash occurred in the shell process.";
    });
    qInfo() << "[Marathon] Crash protection installed (signal handlers active)";

#ifdef Q_OS_LINUX
    // Shell main thread = SCHED_RR/2; render thread is set to RR/1 from
    // WaylandCompositor. See docs/RT_SCHEDULING.md for the full hierarchy.
    if (const int rc = marathon::rt::setCurrentThreadPriority(2); rc != 0) {
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

    auto *sessionStore = new SessionStore(&app);
    qmlRegisterSingletonInstance<SessionStore>("MarathonOS.Shell", 1, 0, "SessionStore",
                                               sessionStore);

    engine.addImageProvider("lunasvg", new LunaSvgImageProvider());

    engine.addImageProvider("lunasvgqrc", new LunaSvgImageProvider());
    qInfo() << "[MarathonShell] LunaSVG image provider registered";

    auto *ctx = engine.rootContext();

    createObject<ScreenMetrics>(ctx, "ScreenMetricsCpp", &app);

    auto *mpris2Controller = new MPRIS2Controller(&app);
    qmlRegisterSingletonInstance<MPRIS2Controller>("MarathonOS.Shell", 1, 0, "MPRIS2Controller",
                                                   mpris2Controller);
    qInfo() << "[MarathonShell]MPRIS2 media controller initialized";

    auto *settingsManager = new SettingsManager(&app);
    qmlRegisterSingletonInstance<SettingsManager>("MarathonOS.Shell", 1, 0, "SettingsManagerCpp",
                                                  settingsManager);
    auto *wallpaperStore = new WallpaperStore(settingsManager, &app);
    qmlRegisterSingletonInstance<WallpaperStore>("MarathonOS.Shell", 1, 0, "WallpaperStore",
                                                 wallpaperStore);

    createObject<WaylandCompositorManager>(ctx, "WaylandCompositorManager", &app);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] Compositor Manager initialized:" << timer.elapsed() << "ms";
    }

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
    const bool gpuHdr = qEnvironmentVariableIntValue("MARATHON_GPU_HDR") != 0;
    ctx->setContextProperty("MARATHON_GPU_HDR", gpuHdr);

#ifdef HAVE_WAYLAND
    ctx->setContextProperty("HAVE_WAYLAND", true);
#else
    ctx->setContextProperty("HAVE_WAYLAND", false);
#endif

    createObject<DesktopFileParser>(ctx, "DesktopFileParserCpp", &app);

    auto *appRegistry = createObject<MarathonAppRegistry>(ctx, "MarathonAppRegistry", &app);
    auto *appStore    = new AppStore(appRegistry, &app);
    qmlRegisterSingletonInstance<AppStore>("MarathonOS.Shell", 1, 0, "AppStore", appStore);
    auto *appScanner =
        createObject<MarathonAppScanner>(ctx, "MarathonAppScanner", appRegistry, &app);
    auto *appInstaller = createObject<MarathonAppInstaller>(ctx, "MarathonAppInstaller",
                                                            appRegistry, appScanner, &app);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] App System initialized:" << timer.elapsed() << "ms";
    }

    createObject<MarathonInputMethodEngine>(ctx, "InputMethodEngine", &app);
    qInfo() << "Input Method Engine initialized";

    auto *appModel  = createObject<AppModel>(ctx, "AppModel", &app);
    auto *taskModel = new TaskModel(&app);
    qmlRegisterSingletonInstance<TaskModel>("MarathonOS.Shell", 1, 0, "TaskModel", taskModel);
    auto *notificationModel = new NotificationModel(&app);
    qmlRegisterSingletonInstance<NotificationModel>("MarathonOS.Shell", 1, 0, "NotificationModel",
                                                    notificationModel);
    auto *navigationRouter = createObject<NavigationRouterCpp>(ctx, "NavigationRouter", &app);
    createObject<StateManagerCpp>(ctx, "StateManager", &app);

    qmlRegisterUncreatableMetaObject(NotificationModel::staticMetaObject, "MarathonOS.Shell", 1, 0,
                                     "NotificationRoles", "Cannot create NotificationRoles enum");

    auto *networkManager = new NetworkManagerCpp(&app);
    qmlRegisterSingletonInstance<NetworkManagerCpp>("MarathonOS.Shell", 1, 0, "NetworkManagerCpp",
                                                    networkManager);
    auto *powerManager = new PowerManagerCpp(&app);
    qmlRegisterSingletonInstance<PowerManagerCpp>("MarathonOS.Shell", 1, 0, "PowerManagerService",
                                                  powerManager);
    auto *rotationManager = createObject<RotationManager>(ctx, "RotationManager", &app);
    auto *displayManager  = new DisplayManagerCpp(powerManager, rotationManager, &app);
    qmlRegisterSingletonInstance<DisplayManagerCpp>("MarathonOS.Shell", 1, 0, "DisplayManagerCpp",
                                                    displayManager);
    auto *audioManager = new AudioManagerCpp(&app);
    qmlRegisterSingletonInstance<AudioManagerCpp>("MarathonOS.Shell", 1, 0, "AudioManagerCpp",
                                                  audioManager);
    auto *modemManager  = createObject<ModemManagerCpp>(ctx, "ModemManagerCpp", &app);
    auto *sensorManager = createObject<SensorManagerCpp>(ctx, "SensorManagerCpp", &app);
    displayManager->setSensorManager(sensorManager);
    auto *bluetoothManager = createObject<BluetoothManager>(ctx, "BluetoothManagerCpp", &app);
    auto *locationManager  = createObject<LocationManager>(ctx, "LocationManager", &app);
    auto *hapticManager    = new HapticManager(&app);
    qmlRegisterSingletonInstance<HapticManager>("MarathonOS.Shell", 1, 0, "HapticManager",
                                                hapticManager);
    createObject<ClipboardManagerCpp>(ctx, "ClipboardManagerCpp", settingsManager, &app);
    auto *alarmManager = createObject<AlarmManagerCpp>(
        ctx, "AlarmManagerCpp", settingsManager, powerManager, audioManager, hapticManager, &app);
    auto *flashlightManager = createObject<FlashlightManagerCpp>(ctx, "FlashlightManagerCpp", &app);
    auto *audioRoutingManager =
        createObject<AudioRoutingManager>(ctx, "AudioRoutingManagerCpp", &app);
    auto *securityManager = new SecurityManager(&app);
    qmlRegisterSingletonInstance<SecurityManager>("MarathonOS.Shell", 1, 0, "SecurityManagerCpp",
                                                  securityManager);

    auto *appLaunchService = new AppLaunchService(appModel, taskModel, &app);
    qmlRegisterSingletonInstance<AppLaunchService>("MarathonOS.Shell", 1, 0, "AppLaunchService",
                                                   appLaunchService);
    createObject<UnifiedSearchServiceCpp>(ctx, "UnifiedSearchService", appModel, appRegistry,
                                          appScanner, settingsManager, navigationRouter,
                                          appLaunchService, &app);

    const QByteArray autoLaunchRaw = qgetenv("MARATHON_AUTO_LAUNCH_APP_ID").trimmed();
    if (!autoLaunchRaw.isEmpty()) {
        const QString autoAppId = QString::fromLocal8Bit(autoLaunchRaw);
        auto          launched  = std::make_shared<bool>(false);
        auto          tryLaunch = [appLaunchService, autoAppId, launched]() {
            if (!appLaunchService || *launched)
                return;
            if (!appLaunchService->compositor() || !appLaunchService->appWindow())
                return;
            *launched = true;
            QTimer::singleShot(0, appLaunchService, [appLaunchService, autoAppId]() {
                qWarning() << "[MarathonShell] Auto-launching app:" << autoAppId;
                appLaunchService->launchApp(autoAppId);
            });
        };
        QObject::connect(appLaunchService, &AppLaunchService::compositorChanged, &app, tryLaunch);
        QObject::connect(appLaunchService, &AppLaunchService::appWindowChanged, &app, tryLaunch);
        QTimer::singleShot(3000, &app, tryLaunch);
    }

    auto *appLifecycleManager = new AppLifecycleManager(taskModel, appLaunchService, &app);
    qmlRegisterSingletonInstance<AppLifecycleManager>("MarathonOS.Shell", 1, 0,
                                                      "AppLifecycleManager", appLifecycleManager);

    auto *powerPolicyController = new PowerPolicyController(powerManager, displayManager, &app);
    qmlRegisterSingletonInstance<PowerPolicyController>(
        "MarathonOS.Shell", 1, 0, "PowerPolicyControllerCpp", powerPolicyController);

    auto *displayPolicyController =
        new DisplayPolicyController(displayManager, settingsManager, &app);
    qmlRegisterSingletonInstance<DisplayPolicyController>(
        "MarathonOS.Shell", 1, 0, "DisplayPolicyControllerCpp", displayPolicyController);

    // logind has HandlePowerKey=ignore (50-marathon.conf), so the shell owns
    // the power button. PowerKeyListener watches every /dev/input/event*
    // that advertises KEY_POWER and emits on key-down; we route the press
    // into the same wake path marathon-dev wake uses.
    auto *powerKeyListener = new PowerKeyListener(&app);
    auto  screenIsOn       = std::make_shared<bool>(true);
    QObject::connect(displayManager, &DisplayManagerCpp::screenStateChanged, &app,
                     [screenIsOn](bool on) { *screenIsOn = on; });
    QObject::connect(powerKeyListener, &PowerKeyListener::powerKeyPressed, displayManager,
                     [displayManager, screenIsOn]() {
                         if (*screenIsOn) {
                             qInfo() << "[MarathonShell] Power key pressed while screen ON "
                                        "— ignored (wake-only first pass)";
                             return;
                         }
                         qInfo() << "[MarathonShell] Power key pressed — waking display";
                         displayManager->setScreenState(true);
                     });
    createObject<PowerBatteryHandlerCpp>(ctx, "PowerBatteryHandler", powerPolicyController,
                                         displayPolicyController, displayManager, hapticManager,
                                         &app);
    auto *audioPolicyController =
        new AudioPolicyController(audioManager, settingsManager, hapticManager, &app);
    qmlRegisterSingletonInstance<AudioPolicyController>(
        "MarathonOS.Shell", 1, 0, "AudioPolicyControllerCpp", audioPolicyController);
    auto *notificationService = new NotificationServiceCpp(
        notificationModel, settingsManager, audioPolicyController, hapticManager, &app);
    qmlRegisterSingletonInstance<NotificationServiceCpp>(
        "MarathonOS.Shell", 1, 0, "NotificationService", notificationService);
    auto *systemStatusStore =
        new SystemStatusStore(powerManager, networkManager, bluetoothManager, modemManager,
                              notificationService, settingsManager, &app);
    qmlRegisterSingletonInstance<SystemStatusStore>("MarathonOS.Shell", 1, 0, "SystemStatusStore",
                                                    systemStatusStore);
    auto *screenshotService = createObject<ScreenshotServiceCpp>(
        ctx, "ScreenshotService", audioPolicyController, hapticManager, notificationService, &app);

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
    auto *systemControlStore = new SystemControlStore(
        networkManager, bluetoothManager, displayManager, flashlightManager, modemManager,
        settingsManager, alarmManager, locationManager, hapticManager, powerManager, audioManager,
        audioPolicyController, screenshotService, &app);
    qmlRegisterSingletonInstance<SystemControlStore>("MarathonOS.Shell", 1, 0, "SystemControlStore",
                                                     systemControlStore);
    auto *uiStore = new UIStore(&app);
    qmlRegisterSingletonInstance<UIStore>("MarathonOS.Shell", 1, 0, "UIStore", uiStore);
    auto *router = new Router(&app);
    qmlRegisterSingletonInstance<Router>("MarathonOS.Shell", 1, 0, "Router", router);
    auto *surfaceRegistry = new SurfaceRegistry(&app);
    qmlRegisterSingletonInstance<SurfaceRegistry>("MarathonOS.Shell", 1, 0, "SurfaceRegistry",
                                                  surfaceRegistry);

    createObject<CursorManager>(ctx, "CursorManager", &app);
    if (debugEnabled || profileMode) {
        qInfo() << "[Profiler] Hardware Managers initialized:" << timer.elapsed() << "ms";
    }

    QObject::connect(audioManager, &AudioManagerCpp::isPlayingChanged, powerManager,
                     [powerManager, audioManager]() {
                         if (audioManager->isPlaying()) {
                             powerManager->acquireWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback started - acquired wakelock";
                         } else {
                             powerManager->releaseWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback stopped - released wakelock";
                         }
                     });
    qInfo() << "[MarathonShell] Audio playback wakelock integration enabled";

    auto *platform = createObject<PlatformCpp>(ctx, "Platform", &app);
    ctx->setContextProperty("PlatformCpp", platform);
    createObject<StatusBarIconServiceCpp>(ctx, "StatusBarIconService", &app);
    qInfo() << "[MarathonShell] Security Manager initialized (PAM + fprintd)";

    auto *wordEngine = createObject<WordEngine>(ctx, "WordEngine", &app);
    wordEngine->setLanguage("en_US");
    wordEngine->setEnabled(true);
    qInfo() << "[MarathonShell] Word Engine initialized";
    auto *emojiPredictor = new EmojiPredictor(&app);
    qmlRegisterSingletonInstance<EmojiPredictor>("MarathonOS.Shell", 1, 0, "EmojiPredictor",
                                                 emojiPredictor);
    auto *phrasePredictor = new PhrasePredictor(&app);
    qmlRegisterSingletonInstance<PhrasePredictor>("MarathonOS.Shell", 1, 0, "PhrasePredictor",
                                                  phrasePredictor);
    auto *dictionary = new Dictionary(wordEngine, emojiPredictor, phrasePredictor, &app);
    qmlRegisterSingletonInstance<Dictionary>("MarathonOS.Shell", 1, 0, "Dictionary", dictionary);
    auto *autoCorrect = new AutoCorrect(dictionary, &app);
    qmlRegisterSingletonInstance<AutoCorrect>("MarathonOS.Shell", 1, 0, "AutoCorrect", autoCorrect);
    auto *languageManager = new LanguageManager(settingsManager, wordEngine, &app);
    qmlRegisterSingletonInstance<LanguageManager>("MarathonOS.Shell", 1, 0, "LanguageManager",
                                                  languageManager);

    auto *rtScheduler = createObject<RTScheduler>(ctx, "RTScheduler", &app);
    if (rtScheduler->isRealtimeKernel()) {
        qInfo() << "[MarathonShell] RT Scheduler initialized (PREEMPT_RT kernel detected)";
        qInfo() << "[MarathonShell]   Current policy:" << rtScheduler->getCurrentPolicy()
                << "Priority:" << rtScheduler->getCurrentPriority();
    }

    qInfo() << "[MarathonShell] Initializing Marathon Service Bus (D-Bus)...";
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCritical() << "[MarathonShell] Failed to connect to D-Bus session bus!";
    } else {
        qInfo() << "[MarathonShell] Connected to D-Bus session bus";

        NotificationDatabase *notifDb = new NotificationDatabase(&app);
        if (!notifDb->initialize()) {
            qWarning() << "[MarathonShell] Failed to initialize notification database";
        }

        notificationModel->loadFromDatabase(notifDb);

        auto *freedesktopNotif = createObject<FreedesktopNotifications>(
            ctx, "FreedesktopNotifications", notifDb, notificationModel, powerManager, &app);
        if (freedesktopNotif->registerService()) {
            qInfo() << "[MarathonShell]  org.freedesktop.Notifications registered";
        }

        auto *unifiedPush = createObject<UnifiedPushDistributor>(
            ctx, "UnifiedPushDistributor", notificationService, settingsManager, &app);
        if (unifiedPush->registerService()) {
            qInfo() << "[MarathonShell]  org.unifiedpush.Distributor.marathon registered";
        }
        createObject<MarathonNtfyClient>(ctx, "NtfyClient", unifiedPush, &app);

        createObject<CarrierProvisioning>(ctx, "CarrierProvisioning", &app);

        qInfo() << "[MarathonShell] Service bus ready (6 services active)";
    }
    if (debugEnabled) {
        qDebug() << "[Profiler] DBus Services initialized:" << timer.elapsed() << "ms";
    }

    auto *permissionManager = new MarathonPermissionManager(&app);
    qmlRegisterSingletonInstance<MarathonPermissionManager>("MarathonOS.Shell", 1, 0,
                                                            "PermissionManager", permissionManager);
    qInfo() << "[MarathonShell] Permission Manager initialized";

    QObject::connect(appLaunchService, &AppLaunchService::appExited, permissionManager,
                     &MarathonPermissionManager::dismissForApp);

    auto *appStoreService =
        createObject<MarathonAppStoreService>(ctx, "AppStoreService", appInstaller, &app);
    qInfo() << "[MarathonShell] App Store Service initialized";

    auto *flatpakManager = createObject<FlatpakManager>(ctx, "FlatpakManager", &app);
    if (debugEnabled && flatpakManager->available()) {
        QObject::connect(flatpakManager, &FlatpakManager::installedAppsChanged, &app,
                         [flatpakManager]() {
                             const QVariantList apps = flatpakManager->installedApps();
                             qInfo() << "[FlatpakManager] installed:" << apps.size();
                             if (!apps.isEmpty())
                                 flatpakManager->requestPermissions(
                                     apps.first().toMap().value("ref").toString());
                         });
        QObject::connect(flatpakManager, &FlatpakManager::permissionsReady, &app,
                         [](const QString &ref, const QVariantMap &perms) {
                             qInfo() << "[FlatpakManager] perms for" << ref
                                     << "sections=" << perms.keys();
                         });
        flatpakManager->refresh();
    }

    // Activity Rings backend — feeds the lock-screen Activity NowBar
    // and the Active Frames Health frame off IIO accelerometer samples
    // through the vendored Oxford C-Step-Counter. Falls back to a
    // demo generator on hardware without an IIO accel device or when
    // MARATHON_MOTION_DEMO=1.
    createObject<MotionDaemon>(ctx, "ActivityService", &app);

    auto *contactsManager    = createObject<ContactsManager>(ctx, "ContactsManager", &app);
    auto *telephonyService   = createObject<TelephonyService>(ctx, "TelephonyService", &app);
    auto *callHistoryManager = createObject<CallHistoryManager>(ctx, "CallHistoryManager", &app);
    auto *smsService         = createObject<SMSService>(ctx, "SMSService", &app);
    auto *mmsManager         = createObject<MmsManager>(ctx, "MmsManager", &app);
    smsService->setMmsManager(mmsManager);
    auto *updateService    = createObject<UpdateService>(ctx, "UpdateService", &app);
    auto *davCalendarStore = createObject<DavCalendarStore>(ctx, "DavCalendarStore", &app);
    auto *davSyncEngine =
        createObject<DavSyncEngine>(ctx, "DavSyncEngine", contactsManager, davCalendarStore, &app);
    createObject<NotificationHandlerCpp>(ctx, "NotificationHandler", notificationService,
                                         navigationRouter, telephonyService, smsService, &app);
    createObject<TelephonyIntegrationCpp>(
        ctx, "TelephonyIntegration", contactsManager, notificationService, powerPolicyController,
        powerManager, displayPolicyController, displayManager, audioPolicyController, hapticManager,
        telephonyService, smsService, sensorManager, &app);

    callHistoryManager->setContactsManager(contactsManager);
    smsService->setContactsManager(contactsManager);

    // Bridges system-observed activity (audio playback, active calls) into
    // AppLifecycleManager capability claims so backgrounded apps holding a
    // capability are kept warm (BackgroundActive) and never frozen.
    new BackgroundTaskObserver(appLifecycleManager, appLaunchService, mpris2Controller,
                               telephonyService, &app);

    // PSI memory pressure listener. Marathon's policy ladder mirrors the
    // industry split: at Moderate (Linux PSI some-avg10 ≥ 5%) apps get a
    // low-memory hint; at Critical (≥ 40%) we proactively kill the
    // longest-frozen app, matching Android's lmkd-on-PSI behavior
    // (psi_partial_stall_ms=70ms on high-perf devices triggers low-mem;
    // 700ms triggers critical). systemd-oomd at the slice level is the
    // belt-and-suspenders fallback if our listener dies.
    auto *pressureMonitor = new MemoryPressureMonitor(&app);
    QObject::connect(pressureMonitor, &MemoryPressureMonitor::pressureLevelChanged,
                     appLifecycleManager,
                     [appLifecycleManager](MemoryPressureMonitor::PressureLevel level, double) {
                         if (level >= MemoryPressureMonitor::High)
                             appLifecycleManager->broadcastLowMemory();
                         if (level >= MemoryPressureMonitor::Critical)
                             appLifecycleManager->killOldestFrozenApp();
                     });

    QObject::connect(telephonyService, &TelephonyService::callStateChanged, audioRoutingManager,
                     [audioRoutingManager](const QString &state) {
                         if (state == "active" || state == "incoming") {
                             audioRoutingManager->startCallAudio();
                         } else if (state == "idle" || state == "terminated") {
                             audioRoutingManager->stopCallAudio();
                         }
                     });
    qInfo() << "[MarathonShell] Audio routing wired to telephony";

    auto *mediaLibraryManager = createObject<MediaLibraryManager>(ctx, "MediaLibraryManager", &app);
    createObject<MusicLibraryManager>(ctx, "MusicLibraryManager", &app);

    {
        auto *ipc = new ShellIpcServer(
            permissionManager, contactsManager, callHistoryManager, telephonyService, smsService,
            mediaLibraryManager, settingsManager, bluetoothManager, displayManager, powerManager,
            audioManager, audioPolicyController, networkManager, hapticManager, securityManager,
            sensorManager, locationManager, alarmManager, audioRoutingManager, updateService,
            davSyncEngine, appStoreService, appLaunchService, appLifecycleManager, appRegistry,
            &app);
        if (!ipc->registerOnSessionBus()) {
            qCritical()
                << "[MarathonShell] Failed to register app IPC on DBus (org.marathonos.Shell)";
        }
    }

    static qint64  callStartTime = 0;
    static QString lastCalledNumber;
    static bool    wasIncoming = false;

    QObject::connect(telephonyService, &TelephonyService::incomingCall, [](const QString &number) {
        callStartTime    = QDateTime::currentMSecsSinceEpoch();
        lastCalledNumber = number;
        wasIncoming      = true;
    });

    QObject::connect(telephonyService, &TelephonyService::callStateChanged, callHistoryManager,
                     [callHistoryManager, telephonyService](const QString &state) {
                         if (state == "active" && callStartTime == 0) {

                             callStartTime    = QDateTime::currentMSecsSinceEpoch();
                             lastCalledNumber = telephonyService->activeNumber();
                             wasIncoming      = false;
                         } else if (state == "idle" || state == "terminated") {

                             if (callStartTime > 0 && !lastCalledNumber.isEmpty()) {
                                 qint64  endTime  = QDateTime::currentMSecsSinceEpoch();
                                 int     duration = (endTime - callStartTime) / 1000;

                                 QString callType;
                                 if (wasIncoming) {

                                     callType = (duration > 0) ? "incoming" : "missed";
                                 } else {
                                     callType = "outgoing";
                                 }

                                 callHistoryManager->addCall(lastCalledNumber, callType,
                                                             callStartTime, duration);
                                 qInfo() << "[MarathonShell] Call logged:" << callType
                                         << lastCalledNumber << duration << "s";

                                 callStartTime = 0;
                                 lastCalledNumber.clear();
                                 wasIncoming = false;
                             }
                         }
                     });
    qInfo() << "[MarathonShell] Call history wired to telephony";

    appModel->loadFromRegistry(appRegistry);

    engine.addImportPath("qrc:/");

    QString userMarathonUIPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    engine.addImportPath(userMarathonUIPath);
    qDebug() << "[QML Import] User-local MarathonUI:" << userMarathonUIPath;

    QString systemMarathonUIPath = "/usr/lib/qt6/qml";
    engine.addImportPath(systemMarathonUIPath);
    qDebug() << "[QML Import] System-wide Qt modules:" << systemMarathonUIPath;

    QString localSystemMarathonUIPath = "/usr/local/lib/qt6/qml";
    engine.addImportPath(localSystemMarathonUIPath);
    qDebug() << "[QML Import] Local System-wide Qt modules:" << localSystemMarathonUIPath;

    QString buildMarathonUIPath = QCoreApplication::applicationDirPath() + "/..";
    engine.addImportPath(buildMarathonUIPath);
    qDebug() << "[QML Import] Build directory:" << buildMarathonUIPath;

    QDir themeCheck1(userMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck2(systemMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck2b(localSystemMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck3(buildMarathonUIPath + "/MarathonUI/Theme");

    bool marathonUIFound = themeCheck1.exists() || themeCheck2.exists() || themeCheck2b.exists() ||
        themeCheck3.exists();

    if (!marathonUIFound) {
        qCritical() << "";
        qCritical() << "========================================================================";
        qCritical() << " FATAL: MarathonUI QML modules not found!";
        qCritical() << "========================================================================";
        qCritical() << "";
        qCritical() << "MarathonUI must be built and installed before running Marathon Shell.";
        qCritical() << "";
        qCritical() << "QUICK FIX:";
        qCritical() << "  cd" << QDir::current().absolutePath();
        qCritical() << "  ./scripts/build-all.sh";
        qCritical() << "";
        qCritical() << "MANUAL BUILD (if build-all.sh fails):";
        qCritical() << "  cd" << QDir::current().absolutePath();
        qCritical() << "  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release";
        qCritical() << "  cmake --build build -j$(nproc)";
        qCritical() << "  cmake --install build  # Installs to ~/.local/share/marathon-ui";
        qCritical() << "";
        qCritical() << "CHECKED PATHS:";
        qCritical() << "  1." << themeCheck1.absolutePath()
                    << (themeCheck1.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  2." << themeCheck2.absolutePath()
                    << (themeCheck2.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  3." << themeCheck2b.absolutePath()
                    << (themeCheck2b.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  4." << themeCheck3.absolutePath()
                    << (themeCheck3.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "";
        qCritical() << "========================================================================";
        qCritical() << "";

    } else {
        qInfo() << "[MarathonShell] MarathonUI modules found";
        if (themeCheck1.exists())
            qDebug() << "  - Using user-local installation";
        else if (themeCheck2.exists())
            qDebug() << "  - Using system-wide installation";
        else if (themeCheck3.exists())
            qDebug() << "  - Using build directory (development mode)";
    }

    const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));

    qRegisterMetaType<GeoClueTimestamp>("GeoClueTimestamp");
    qDBusRegisterMetaType<GeoClueTimestamp>();

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

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }

    QTimer::singleShot(
        0, &app, [&app, settingsManager, appModel, appRegistry, appScanner, permissionManager]() {
            const QStringList searchPaths = {
                "/usr/share/applications", "/usr/local/share/applications",
                QDir::homePath() + "/.local/share/applications",
                "/var/lib/flatpak/exports/share/applications",
                QDir::homePath() + "/.local/share/flatpak/exports/share/applications"};

            const bool filterMobile = settingsManager->filterMobileFriendlyApps();

#ifdef HAVE_QT_CONCURRENT
            auto *watcher = new QFutureWatcher<QVariantList>(&app);
            QObject::connect(watcher, &QFutureWatcher<QVariantList>::finished, &app,
                             [watcher, appModel]() {
                                 const QVariantList nativeApps = watcher->result();
                                 appModel->addApps(nativeApps);
                                 watcher->deleteLater();
                             });

            QFuture<QVariantList> future = QtConcurrent::run([searchPaths, filterMobile]() {
                DesktopFileParser parser;
                return parser.scanApplications(searchPaths, filterMobile);
            });
            watcher->setFuture(future);
#else
        DesktopFileParser parser;
        const QVariantList nativeApps = parser.scanApplications(searchPaths, filterMobile);
        appModel->addApps(nativeApps);
#endif

            auto grantProtected = [permissionManager, appRegistry](const QString &appId) {
                if (!permissionManager || !appRegistry)
                    return;
                auto *info = appRegistry->getAppInfo(appId);
                if (!info || !info->isProtected)
                    return;
                for (const QString &perm : info->permissions) {
                    if (!perm.isEmpty())
                        permissionManager->setPermission(appId, perm, true, true);
                }
            };

            QObject::connect(appScanner, &MarathonAppScanner::appDiscovered, &app, grantProtected);
            QObject::connect(appScanner, &MarathonAppScanner::scanComplete, &app,
                             [appModel, appRegistry, grantProtected](int) {
                                 for (const QString &id : appRegistry->getAllAppIds())
                                     grantProtected(id);
                                 appModel->loadFromRegistry(appRegistry);
                             });

#ifdef HAVE_QT_CONCURRENT
            appScanner->scanApplicationsAsync();
#else
        appScanner->scanApplications();
#endif

            QStringList flatpakDirs;
            for (const QString &p :
                 {QStringLiteral("/var/lib/flatpak/exports/share/applications"),
                  QDir::homePath() +
                      QStringLiteral("/.local/share/flatpak/exports/share/applications")}) {
                if (QDir(p).exists())
                    flatpakDirs.append(p);
            }
            if (!flatpakDirs.isEmpty()) {
                auto *flatpakWatcher = new QFileSystemWatcher(&app);
                flatpakWatcher->addPaths(flatpakDirs);

                auto *debounce = new QTimer(&app);
                debounce->setSingleShot(true);
                debounce->setInterval(500);

                QObject::connect(flatpakWatcher, &QFileSystemWatcher::directoryChanged, debounce,
                                 qOverload<>(&QTimer::start));

                QObject::connect(
                    debounce, &QTimer::timeout, &app, [appModel, flatpakDirs, filterMobile]() {
                        DesktopFileParser  parser;
                        const QVariantList apps =
                            parser.scanApplications(flatpakDirs, filterMobile);

                        QSet<QString> seen;
                        for (const QVariant &v : apps)
                            seen.insert(v.toMap().value(QStringLiteral("id")).toString());

                        const QStringList existing =
                            appModel->appIdsByType(QStringLiteral("flatpak"));
                        for (const QString &id : existing) {
                            if (!seen.contains(id))
                                appModel->removeApp(id);
                        }
                        appModel->addApps(apps);
                    });
            }
        });

    qDebug() << "Marathon OS Shell started";
    return QGuiApplication::exec();
}
