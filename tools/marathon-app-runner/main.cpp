#include <QGuiApplication>
#include <QQuickView>
#include <memory>
#include <QQuickWindow>
#include <QScreen>
#include "services/touchresampler.h"
#include <QSGRendererInterface>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlListReference>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QDebug>
#include <QUrl>
#include <QTimer>
#include <QQuickItem>
#include <QFile>
#include <QTextStream>
#include <QColor>
#include <QDateTime>
#include <QElapsedTimer>
#include <QTimeZone>
#include <QVariantMap>
#include <QtQml/qqml.h>
#include <QDBusConnection>
#include <QEventLoop>
#include <QSocketNotifier>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QSurfaceFormat>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>


// A Rust client of the shell under `name`: a context property and, when apps
// compiled against the shell module look it up as one, a MarathonOS.Shell
// singleton.
template <typename T> T *exposeClient(QQmlContext *ctx, const char *name, bool singleton = true) {
    auto *client = new T();
    client->setParent(QCoreApplication::instance());
    ctx->setContextProperty(QLatin1String(name), client);
    if (singleton)
        qmlRegisterSingletonInstance<T>("MarathonOS.Shell", 1, 0, name, client);
    return client;
}

#ifdef HAVE_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

#include "marathon-app-native/src/apps.cxxqt.h"
#include "marathon-app-native/src/keel.cxxqt.h"
#include "marathon-app-native/src/runner.cxxqt.h"
#include "marathon-app-native/src/world_clock.cxxqt.h"

#include "diag/frametiming.h"
#include "marathon-app-native/src/rt.cxxqt.h"

#ifdef Q_OS_LINUX
// Foreground app: main thread RR/4, render thread RR/3 -- see
// docs/RT_SCHEDULING.md for the full hierarchy and rationale.
constexpr int           kForegroundMainPriority   = 4;
constexpr int           kForegroundRenderPriority = 3;

static std::atomic<int> g_desiredRenderPriority{0};

// Render thread (called from beforeSynchronizing on the render thread).
static void applyRenderPriorityIfNeeded() {
    static int last = -1;
    const int  want = g_desiredRenderPriority.load(std::memory_order_relaxed);
    if (want == last)
        return;
    const int rc = marathon::rt::set_thread_priority(want);
    last         = want;
    if (rc != 0) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            qInfo() << "[AppRunner] Render-thread RT elevation skipped (rtprio rlimit not "
                       "granted):"
                    << strerror(rc);
        }
    }
}

// Main thread (called directly from activeChanged on main thread).
static void applyMainPriorityForActive(bool active) {
    static int last = -1;
    const int  want = active ? kForegroundMainPriority : 0;
    if (want == last)
        return;
    const int rc = marathon::rt::set_thread_priority(want);
    last         = want;
    if (rc != 0) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            qInfo() << "[AppRunner] Main-thread RT elevation skipped:" << strerror(rc);
        }
    }
}
#endif

#include "marathon-app-native/src/alarms.cxxqt.h"
#include "marathon-app-native/src/android.cxxqt.h"
#include "marathon-app-native/src/audio.cxxqt.h"
#include "marathon-app-native/src/bluetooth.cxxqt.h"
#include "marathon-app-native/src/contacts.cxxqt.h"
#include "marathon-app-native/src/dav.cxxqt.h"
#include "marathon-app-native/src/display.cxxqt.h"
#include "marathon-app-native/src/haptics.cxxqt.h"
#include "marathon-app-native/src/history.cxxqt.h"
#include "marathon-app-native/src/lifecycle.cxxqt.h"
#include "marathon-app-native/src/location.cxxqt.h"
#include "marathon-app-native/src/media.cxxqt.h"
#include "marathon-app-native/src/modem.cxxqt.h"
#include "marathon-app-native/src/mail.cxxqt.h"
#include "marathon-app-native/src/maps.cxxqt.h"
#include "marathon-app-native/src/mpris.cxxqt.h"
#include "marathon-app-native/src/music.cxxqt.h"
#include "marathon-app-native/src/navigation.cxxqt.h"
#include "marathon-app-native/src/network.cxxqt.h"
#include "marathon-app-native/src/notifications.cxxqt.h"
#include "marathon-app-native/src/permissions.cxxqt.h"
#include "marathon-app-native/src/power.cxxqt.h"
#include "marathon-app-native/src/security.cxxqt.h"
#include "marathon-app-native/src/sensors.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/settings_app.cxxqt.h"
#include "marathon-app-native/src/shell.cxxqt.h"
#include "marathon-app-native/src/sms.cxxqt.h"
#include "marathon-app-native/src/store.cxxqt.h"
#include "marathon-app-native/src/stores.cxxqt.h"
#include "marathon-app-native/src/telephony.cxxqt.h"
#include "marathon-app-native/src/terminal.cxxqt.h"
#include "marathon-app-native/src/updates.cxxqt.h"
#include "platformtypes.h"
#include "terminalrenderer.h"
#include "marathon-app-native/src/wallpapers.cxxqt.h"
#include "marathon-app-native/src/calendar.cxxqt.h"
#include "marathon-app-native/src/camera.cxxqt.h"

// The app root's Back or Forward handler (`method`), else its plain signal
// (`fallback`), which counts as handled.
static bool invokeRoot(QObject *root, const char *method, const char *fallback) {
    if (!root)
        return false;
    QVariant ret;
    if (QMetaObject::invokeMethod(root, method, Qt::DirectConnection, Q_RETURN_ARG(QVariant, ret)))
        return ret.toBool();
    QMetaObject::invokeMethod(root, fallback, Qt::DirectConnection);
    return true;
}

// A Keel app's window close (xdg_toplevel.close from the task switcher)
// becomes CloseRequested: a close before the app is closing is held back and
// reported, so the app gets its grace period before the runner quits. Quit
// closes the window too, which then passes.
class KeelCloseGuard : public QObject {
  public:
    KeelCloseGuard(std::shared_ptr<bool> closing, std::function<void()> beginClose, QObject *parent)
        : QObject(parent)
        , m_closing(std::move(closing))
        , m_beginClose(std::move(beginClose)) {}

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (event->type() != QEvent::Close || *m_closing)
            return QObject::eventFilter(watched, event);
        event->ignore();
        m_beginClose();
        return true;
    }

  private:
    std::shared_ptr<bool> m_closing;
    std::function<void()> m_beginClose;
};

// A page that focused itself while the app was built (Keel's initial page
// goes Active synchronously) holds focus somewhere below the root.
static bool subtreeHasFocus(const QQuickItem *item) {
    const QList<QQuickItem *> children = item->childItems();
    for (const QQuickItem *child : children) {
        if (child->hasFocus() || subtreeHasFocus(child))
            return true;
    }
    return false;
}

// MarathonOS.Shell roots, ahead of Qt's defaults. App-independent, so a pool
// spare sets them up before it is adopted.
static int sharedImportPathCount = 0;
static void addSharedImportPaths(QQmlEngine *engine) {
    const QStringList roots = marathon::runner::shell_import_roots(QCoreApplication::applicationDirPath());
    engine->setImportPathList(roots + engine->importPathList());
    sharedImportPathCount = roots.size();
}

int main(int argc, char *argv[]) {
    // Startup profiling (MARATHON_STARTUP_TIMING=1). Times the app-runner's
    // cold-start phases so launch cost is measurable — the prerequisite for
    // any launch-speed work (there is no warm runner pool; every launch is a
    // full Qt process spawn). Off by default; zero cost when unset.
    QElapsedTimer startupTimer;
    startupTimer.start();
    const bool logStartup = qEnvironmentVariableIntValue("MARATHON_STARTUP_TIMING") != 0;

    // Pool mode (--pool): no app id yet; WebEngine apps never adopt from
    // the pool, so STAGE 1 is skipped entirely.
    marathon::runner::Launch launch = marathon::runner::launch();
    const bool               poolMode = launch.pool;

    // STAGE 1: Pre-QGuiApplication. We peek at the manifest to learn
    // which Qt modules this app needs at process scope (currently just
    // WebEngine). The cost of loading Chromium is then paid by app
    // processes that actually use it, not by the shell.
    if (!poolMode) {
        const QString earlyAppId = launch.app_id;
        if (marathon::apps::requiresQtModule(earlyAppId, QStringLiteral("webengine"))) {
#ifdef HAVE_WEBENGINE
                    // Keep Chromium's own sandbox enabled — the parent
                    // bwrap recipe omits --unshare-user-try for webengine
                    // apps (see AppLaunchService::launchMarathonApp) so
                    // Chromium can nest its own user-namespace unshare.
                    // We still pass --disable-dev-shm-usage because the
                    // sandboxed /dev/shm is tmpfs-sized to defaults and
                    // Chromium's larger buffer pages can hit ENOSPC.
                    {
                        // Force Qt's scene-graph onto the OpenGL RHI backend.
                        // Without this Qt's RHI auto-detect on Pi 5 V3D + bwrap
                        // tmpfs /home picks QSGSoftwareRenderer because the
                        // initial EGL probe fails (the bwrap-mounted /home is
                        // tmpfs and the default-device EGL fd lookup misses).
                        // Software renderer then SIGSEGVs inside
                        // RenderWidgetHostViewQtDelegateItem::updatePaintNode
                        // the first time WebEngine tries to paint -- because
                        // WebEngine produces a GL-backed QSGNode the software
                        // renderer can't walk. Forcing OpenGL up-front makes
                        // Qt use the v3d EGL+GBM path that actually works.
                        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
                        qputenv("QSG_RHI_BACKEND", "opengl");

                        // Qt WebEngine REQUIRES Qt::AA_ShareOpenGLContexts so
                        // the GPU process's GL context can share textures
                        // with the Qt scene-graph context. Without it the
                        // render thread calls QOpenGLContext::functions() on
                        // a null/non-current context and SIGSEGVs the moment
                        // WebEngine tries to schedule its first paint -- the
                        // crash trace is identical to "no scene-graph
                        // context" upstream filed bugs.
                        QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

                        QByteArray flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
                        // Qt's Chromium build does NOT include the Wayland Ozone
                        // backend -- passing --ozone-platform=wayland triggers
                        // FATAL "Invalid ozone platform: wayland" at startup
                        // (verified on Pi 5 / postmarketOS edge, 2026-06-15).
                        // Qt WebEngine uses Qt's QPA integration for window
                        // surface plumbing; dmabuf passthrough still works
                        // because Qt's wayland QPA exports buffer handles via
                        // the QWindow itself, not through Chromium's Ozone.
                        // --ignore-gpu-blocklist + --enable-gpu-rasterization
                        //   + --enable-zero-copy: Chromium's default blocklist
                        //   disables the GPU on most embedded GL ES drivers
                        //   (V3D, Adreno, Mali) treating them as
                        //   not-good-enough; on this hardware they are.
                        // --disable-dev-shm-usage: sandboxed /dev/shm is tmpfs-
                        //   sized to defaults; Chromium's larger buffer pages
                        //   hit ENOSPC.
                        // NOTE: --use-gl=egl deliberately omitted. With Qt
                        // 6.10 the RHI scene-graph backend is selected via
                        // QQuickWindow::setGraphicsApi above; forcing
                        // Chromium's GL implementation on top of that
                        // triggers Qt's "--use-gl=egl is set with unsupported
                        // SceneGraph Backend. Expect troubles!" warning and
                        // the GL context init fails. Chromium auto-picks the
                        // platform-correct GL implementation when left alone.
                        const QByteArray needed = "--disable-dev-shm-usage "
                                                  "--ignore-gpu-blocklist "
                                                  "--enable-gpu-rasterization "
                                                  "--enable-zero-copy";
                        if (flags.isEmpty())
                            flags = needed;
                        else
                            flags = flags + " " + needed;
                        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
                    }
                    QtWebEngineQuick::initialize();
#else
                    qWarning() << "[marathon-app-runner] App" << earlyAppId
                               << "declares requiresQtModules=[webengine] but this"
                                  " build of marathon-app-runner was compiled without"
                                  " HAVE_WEBENGINE -- WebEngineView will fail to load.";
#endif
        }
    }

    // Pin QSurfaceFormat::defaultFormat() to OpenGLES 2.0 AFTER
    // QtWebEngineQuick::initialize() (it sets its own defaultFormat to
    // desktop OpenGL for the Chromium GPU process shared context) and
    // BEFORE QGuiApplication (QRhi's probe reads defaultFormat during
    // platform plugin init). QRhi's temp-context probe (the path that
    // prints "QRhiGles2: Failed to create temporary context") asks for
    // EGL_OPENGL_API by default. On Mesa stacks where the EGL display
    // advertises EGL_OPENGL_ES_BIT only (etnaviv on GC7000Lite/HALTI0,
    // lima, v3d), Mesa returns __DRI_CTX_ERROR_BAD_VERSION → EGL_BAD_MATCH
    // and QRhi gives up — Qt does NOT walk down ES versions like GTK4
    // does. Setting format explicitly to GLES 2.0 here resolves Qt's
    // RHI request to EGL_OPENGL_ES_API + EGL_OPENGL_ES2_BIT and the
    // probe succeeds. Verified against egl_dri2.c#L1180 and
    // qrhigles2.cpp.
    {
        QSurfaceFormat fmt;
        fmt.setRenderableType(QSurfaceFormat::OpenGLES);
        fmt.setMajorVersion(2);
        fmt.setMinorVersion(0);
        fmt.setProfile(QSurfaceFormat::NoProfile);
        fmt.setDepthBufferSize(24);
        fmt.setStencilBufferSize(8);
        fmt.setSamples(0);
        fmt.setSwapInterval(1);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName("marathon-app-runner");
    QCoreApplication::setOrganizationName("Marathon OS");

    // Mirror the shell's choice: force QtRendering globally so every Text
    // resolves Sora via the FontLoader instead of fontconfig (which falls
    // back to Noto Sans on this build).
    QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);

    std::unique_ptr<QQuickView>                   pooledView;
    std::unique_ptr<marathon::platform::KeelHost> keelHost;
    // Keel reads its host environment when its plugin first creates the Shell
    // client, which in a pool spare happens during warm-up, so the host must
    // exist before then.
    auto startKeelHost = [&keelHost]() {
        keelHost = std::make_unique<marathon::platform::KeelHost>();
        if (!keelHost->start(qRound(QGuiApplication::primaryScreen()->physicalDotsPerInch()))) {
            qWarning() << "[marathon-app-runner] Keel host failed to start";
            keelHost.reset();
        }
    };
    if (poolMode) {
        // Warm the GL stack off the critical path: EGL display init, the
        // Mesa driver load, and the first context creation otherwise land
        // inside the adopted launch's window-to-frame span.
        {
            QOffscreenSurface warmSurface;
            warmSurface.create();
            QOpenGLContext warmCtx;
            if (warmCtx.create() && warmCtx.makeCurrent(&warmSurface))
                warmCtx.doneCurrent();
        }

        // Load the QML modules every app uses, in the engine the adopted
        // app will run in: musl resolves all of a plugin's relocations at
        // dlopen, and compiled types stay in the engine's type loader.
        // Each type is also created once and destroyed: an app's first
        // instance of a type pays for its property caches, bindings,
        // singletons (Theme), fonts and the image plugins.
        startKeelHost();
        pooledView = std::make_unique<QQuickView>();
        addSharedImportPaths(pooledView->engine());
        {
            const QStringList importPaths = pooledView->engine()->importPathList();
            const bool        silica =
                std::any_of(importPaths.cbegin(), importPaths.cend(), [](const QString &p) {
                    return QFile::exists(p + QStringLiteral("/Sailfish/Silica/qmldir"));
                });
            QByteArray warm = "import QtQuick\n"
                              "import QtQuick.Controls\n"
                              "import QtQuick.Layouts\n"
                              "import QtQuick.Shapes\n"
                              "import QtQuick.Effects\n";
            if (silica)
                warm += "import Sailfish.Silica 1.0 as Silica\n"
                        "import Marathon.Silica 1.0 as MS\n"
                        "import Nemo.Configuration 1.0 as NC\n";
            warm += "QtObject {\n";
            if (silica)
                warm += "    property list<Component> silica: [\n"
                        "        Component { MS.ApplicationWindow {} }, Component { MS.Page {} },\n"
                        "        Component { MS.SilicaFlickable {} }, Component { MS.SilicaListView {} },\n"
                        "        Component { MS.PullDownMenu {} }, Component { MS.MenuItem {} },\n"
                        "        Component { MS.PageHeader {} }, Component { MS.ListItem {} },\n"
                        "        Component { MS.ContextMenu {} }, Component { MS.RemorseItem {} },\n"
                        "        Component { Silica.Label {} }, Component { MS.Button {} },\n"
                        "        Component { MS.TextField {} }, Component { MS.TextArea {} },\n"
                        "        Component { MS.TextSwitch {} }, Component { MS.Slider {} },\n"
                        "        Component { MS.SectionHeader {} }, Component { Silica.ViewPlaceholder {} },\n"
                        "        Component { Silica.VerticalScrollDecorator {} }, Component { MS.Dialog {} },\n"
                        "        Component { MS.TabView {} }, Component { MS.ComboBox {} },\n"
                        "        Component { MS.IconButton {} }, Component { MS.BackgroundItem {} },\n"
                        "        Component { MS.SearchField {} }, Component { MS.ValueButton {} },\n"
                        "        Component { MS.DialogHeader {} }, Component { MS.RemorsePopup {} },\n"
                        "        Component { Silica.DetailItem {} }, Component { Silica.Icon {} },\n"
                        "        Component { Silica.InfoLabel {} }, Component { Silica.BusyIndicator {} },\n"
                        "        Component { NC.ConfigurationValue {} }\n"
                        "    ]\n";
            warm += "}\n";
            QQmlComponent warmComponent(pooledView->engine());
            warmComponent.setData(warm, QUrl());
            if (warmComponent.isError())
                qWarning() << "[marathon-app-runner] pool: QML warm-up failed:"
                           << warmComponent.errorString();
            else {
                std::unique_ptr<QObject> warmed(warmComponent.create());
                const QQmlListReference  types(warmed.get(), "silica");
                for (qsizetype i = 0; i < types.count(); ++i)
                    delete qobject_cast<QQmlComponent *>(types.at(i))->create();
            }
        }

        // Keep the warmed pages resident while the pool idles. Reclaim to
        // zram during idle is what made the v1 pool lose to cold launch:
        // adoption faulted the Qt heap + warmed GL state back in (~800 ms).
        // MCL_ONFAULT pins only pages already touched (the warm-up's), not
        // every page of every linked library: without it the spare locked
        // ~600 MB, mostly untouched WebEngine, LLVM and codec text. If the
        // memlock rlimit is too low (bwrap drops CAP_IPC_LOCK) we fall back
        // to periodically touching the full resident set instead.
        const bool poolLocked = (::mlockall(MCL_CURRENT | MCL_FUTURE | MCL_ONFAULT) == 0);
        if (!poolLocked)
            qWarning() << "[marathon-app-runner] pool: mlockall failed ("
                       << ::strerror(errno) << ") - using page-touch keepalive";

        // Wait on the event loop, not a blocking read, so Wayland events
        // pump normally while the spare idles.
        QByteArray line;
        {
            ::fcntl(0, F_SETFL, ::fcntl(0, F_GETFL) | O_NONBLOCK);
            QEventLoop      wait;
            QSocketNotifier notifier(0, QSocketNotifier::Read);
            QObject::connect(&notifier, &QSocketNotifier::activated, &wait, [&line, &wait]() {
                char    c = 0;
                ssize_t n = 0;
                while ((n = ::read(0, &c, 1)) == 1) {
                    if (c == '\n') {
                        wait.quit();
                        return;
                    }
                    line.append(c);
                }
                if (n == 0) {
                    line.clear();
                    wait.quit();
                }
            });
            // The touch-keepalive only matters when we could not lock:
            // mlockall already guarantees residency, so skip the wasteful
            // full-set walk in that case.
            QTimer keepalive;
            if (!poolLocked) {
                keepalive.setInterval(3000);
                QObject::connect(&keepalive, &QTimer::timeout, &keepalive,
                                 marathon::runner::touch_resident_pages);
                keepalive.start();
                marathon::runner::touch_resident_pages();
            }
            wait.exec();
        }
        // The spare now becomes the launched app: drop the lock so the app's
        // memory is reclaimable again when it is backgrounded/frozen — leaving
        // MCL_FUTURE in place would pin everything the adopt path allocates.
        if (poolLocked)
            ::munlockall();
        launch = marathon::runner::adopt(line);
        if (launch.app_id.isEmpty()) {
            // EOF without a message: the shell went away or drained the pool.
            if (line.isEmpty())
                return 0;
            qCritical() << "[marathon-app-runner] Bad pool adopt message:" << line;
            return 2;
        }
        // Report adopt -> frame: the portion of launch the pool influences.
        startupTimer.restart();
        if (logStartup) {
            qWarning().noquote() << "[startup]" << launch.app_id << "pooled-adopt";
            marathon::runner::log_startup(launch.app_id, "pooled-adopt", 0);
        }
    } else if (launch.app_id.isEmpty()) {
        qCritical() << "[marathon-app-runner] Missing --app-id";
        return 2;
    }
    const QString appId             = launch.app_id;
    const QString launchRoute       = launch.route;
    const QString launchRouteParams = launch.route_params;

    QGuiApplication::setDesktopFileName(appId);

    // Read once, when the app's QML first imports Keel.Actions.
    {
        const QString keelAppId = QStringLiteral("org.marathonos.") + appId;
        const QString manifest  = QStandardPaths::locate(
            QStandardPaths::GenericDataLocation,
            QStringLiteral("keel/actions/%1.json").arg(keelAppId));
        if (!manifest.isEmpty()) {
            qputenv("KEEL_ACTIONS_MANIFEST", manifest.toUtf8());
            qputenv("KEEL_ACTIONS_APP_ID", keelAppId.toUtf8());
        }
    }

    // Load only the app's manifest now. System apps need the complete app
    // model for pickers and notification toggles, but that scan waits until
    // after the first frame.
    auto *registry = new AppRegistry();
    registry->setParent(QCoreApplication::instance());
    if (!registry->load(appId)) {
        qCritical() << "[marathon-app-runner] No app" << appId;
        return 3;
    }
    const QVariantMap info        = registry->getApp(appId);
    const QString     appName     = info.value(QStringLiteral("name")).toString();
    const QString     appPath     = info.value(QStringLiteral("absolutePath")).toString();
    const QString     entryPoint  = info.value(QStringLiteral("entryPoint")).toString();
    const QStringList permissions = info.value(QStringLiteral("permissions")).toStringList();

    const bool viewPrewarmed = pooledView != nullptr;
    std::unique_ptr<QQuickView> ownedView =
        pooledView ? std::move(pooledView) : std::make_unique<QQuickView>();
    QQuickView &view = *ownedView;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setTitle(appName);

    if (permissions.contains(QStringLiteral("system"))) {
        QObject::connect(&view, &QQuickWindow::frameSwapped, registry,
                         [registry]() { registry->loadAll(); }, Qt::SingleShotConnection);
    }

    view.setColor(Qt::transparent);

#ifdef Q_OS_LINUX
    // On window active-state change (handler runs on GUI/main thread):
    //   1. Elevate / demote the main thread directly (we're on it).
    //   2. Set desired render-thread priority for the render thread to pick up.
    //   3. view.update() forces one more sync so beforeSynchronizing fires once
    //      more -- guarantees a demotion lands on the render thread even when
    //      the app has otherwise stopped requesting frames (backgrounded).
    QObject::connect(&view, &QWindow::activeChanged, &view, [&view]() {
        const bool active = view.isActive();
        applyMainPriorityForActive(active);
        g_desiredRenderPriority.store(active ? kForegroundRenderPriority : 0,
                                      std::memory_order_relaxed);
        view.update();
    });
    QObject::connect(
        &view, &QQuickWindow::beforeSynchronizing, &view, []() { applyRenderPriorityIfNeeded(); },
        Qt::DirectConnection);
#endif

    if (qEnvironmentVariableIntValue("MARATHON_FRAME_TIMING") != 0)
        marathon::diag::installFrameTimingTracker(&view, QStringLiteral("app:%1").arg(appId));

    // The panel reports slower than the display (43 Hz on the HackberryPi):
    // the app samples the finger at its own frame time, as Android apps do,
    // so a drag moves every frame. The shell forwards the touch raw.
    // MARATHON_APP_TOUCH_RESAMPLE=0 turns it off.
    if (qEnvironmentVariable("MARATHON_APP_TOUCH_RESAMPLE") != QLatin1String("0"))
        new TouchResampler(&view, view.contentItem());

    const int w = qEnvironmentVariableIntValue("MARATHON_APP_WIDTH") > 0 ?
        qEnvironmentVariableIntValue("MARATHON_APP_WIDTH") :
        540;
    const int h = qEnvironmentVariableIntValue("MARATHON_APP_HEIGHT") > 0 ?
        qEnvironmentVariableIntValue("MARATHON_APP_HEIGHT") :
        1140;
    view.resize(w, h);

    if (!keelHost)
        startKeelHost();
    if (keelHost) {
        // The shell draws the ambience behind a Keel app, which leaves its
        // background transparent; only these windows pay for alpha blending.
        QSurfaceFormat format = view.format();
        format.setAlphaBufferSize(8);
        view.setFormat(format);
    }
    if (keelHost)
        QObject::connect(&view, &QWindow::activeChanged, keelHost.get(),
                         [&view, host = keelHost.get()]() { host->setActive(view.isActive()); });

    // A Keel app is told to close (CloseRequested) and given a second to save,
    // whether the close comes from the task switcher or as SIGTERM.
    if (keelHost) {
        auto closing    = std::make_shared<bool>(false);
        auto beginClose = [host = keelHost.get(), closing]() {
            if (*closing)
                return;
            *closing = true;
            host->requestClose();
            QTimer::singleShot(1000, qApp, &QCoreApplication::quit);
        };
        view.installEventFilter(new KeelCloseGuard(closing, beginClose, &view));
        QObject::connect(keelHost.get(), &marathon::platform::KeelHost::closeRequested, &view,
                         beginClose);
    }

    QQmlEngine *engine = view.engine();

    if (!viewPrewarmed)
        addSharedImportPaths(engine);
    if (QDir(appPath).exists()) {
        QStringList paths = engine->importPathList();
        paths.insert(sharedImportPathCount, appPath);
        engine->setImportPathList(paths);
    }

    engine->addImportPath("qrc:/");
    engine->addImportPath(":/");

    auto *ctx = view.rootContext();
    ctx->setContextProperty("MarathonAppRegistry", registry);

    // Mirror the shell's MARATHON_DEBUG flag into the runner so Logger.info()
    // and the test-app auto-run path actually emit. Without this, every
    // Logger.info() in app QML is silently dropped because Constants.qml's
    // debugMode resolves to false in the runner process.
    {
        const QByteArray dbg = qgetenv("MARATHON_DEBUG");
        const bool       on  = (dbg == "1" || dbg.toLower() == "true");
        ctx->setContextProperty("MARATHON_DEBUG_ENABLED", on);
    }

    // Expose the launch route so apps can show a route-specific entry point
    // (the lock-screen Emergency affordance launches phone with /emergency).
    ctx->setContextProperty("MARATHON_APP_ROUTE", launchRoute);
    ctx->setContextProperty("MARATHON_APP_ROUTE_PARAMS", launchRouteParams);

    // App's install root on disk — e.g. /usr/share/marathon-apps/maps/
    // or ~/.local/share/marathon/apps/<id>/files/. Maps uses this to build a
    // file:// URL for its tile_providers manifest because QtLocation's
    // OSM plugin reads providersrepository.address via QNAM and qrc://
    // URLs sometimes don't survive that round trip.
    ctx->setContextProperty("MARATHON_APP_PATH", appPath);

    // The shell forwards its current user scale factor and detected DPI in
    // env vars so the app can size in lockstep with shell chrome. Without
    // this, Constants.scaleFactor inside the sandbox always evaluates to
    // 1.0 (no SettingsManagerCpp / ScreenMetricsCpp inside the bwrap), so
    // the status bar can be 2x while app content stays at 1x.
    {
        bool         ok        = false;
        const double envScale  = qEnvironmentVariable("MARATHON_USER_SCALE", "1.0").toDouble(&ok);
        const double userScale = (ok && envScale > 0) ? envScale : 1.0;
        const double envDpi    = qEnvironmentVariable("MARATHON_DPI", "160.0").toDouble(&ok);
        const double dpi       = (ok && envDpi > 0) ? envDpi : 160.0;
        ctx->setContextProperty("MARATHON_USER_SCALE", userScale);
        ctx->setContextProperty("MARATHON_DPI", dpi);

        // Screen metrics. ScreenMetricsCpp is not registered inside the
        // runner, so Constants.screenWidth/screenHeight (and everything
        // derived: heightScaleFactor, isTallScreen, safeArea*) were 0/false
        // in every app — breaking any layout keyed off screen dimensions.
        // Forward the real screen size from the shell as a fallback, mirroring
        // the MARATHON_DPI / MARATHON_USER_SCALE pattern above.
        const int envScreenW = qEnvironmentVariableIntValue("MARATHON_SCREEN_WIDTH");
        const int envScreenH = qEnvironmentVariableIntValue("MARATHON_SCREEN_HEIGHT");
        ctx->setContextProperty("MARATHON_SCREEN_WIDTH", envScreenW > 0 ? envScreenW : w);
        ctx->setContextProperty("MARATHON_SCREEN_HEIGHT", envScreenH > 0 ? envScreenH : h);

        // MARATHON_LAYER_SAMPLES + MARATHON_GPU_HDR mirror the shell-side
        // exposures (shell/main.cpp). Apps need these too — every
        // layer-wrapped QML item in shared shell components reads
        // Constants.layerSamples, AppBackdropBlur reads Constants.gpuHdr.
        // Without these context properties the runner falls back to
        // hardcoded defaults that don't match the device's GPU capability.
        bool      samplesOk = false;
        const int envLayerSamples =
            qEnvironmentVariableIntValue("MARATHON_LAYER_SAMPLES", &samplesOk);
        const int layerSamples = samplesOk ? envLayerSamples : 4;
        ctx->setContextProperty("MARATHON_LAYER_SAMPLES", layerSamples);
        const bool gpuHdr = qEnvironmentVariableIntValue("MARATHON_GPU_HDR") != 0;
        ctx->setContextProperty("MARATHON_GPU_HDR", gpuHdr);
    }

    const auto hasPerm = [&](const QString &perm) -> bool {
        return std::find(permissions.begin(), permissions.end(), perm) !=
            permissions.end();
    };

    // Construct only the IPC clients whose permissions the app actually
    // declared. Each client constructor does a sync D-Bus introspect + a
    // handful of signal subscriptions + an initial state refresh -- across
    // ~13 clients that's ~50-150 round-trips on cold start, none of which a
    // perm-less app like Calculator can use anyway (the shell rejects every
    // call with AccessDenied).
    //
    // Permissions, Navigation and Haptics are unconditional:
    // every app uses back/close gestures (Navigation), Marathon UI hooks
    // haptic feedback on standard buttons, and apps need Permissions to
    // introspect their own grants.
    // Unconditional: every app gets the world-clock / timezone helper
    // (lightweight, no IPC, no permissions).
    {
        auto *worldClock = new marathon::platform::WorldClock();
        worldClock->setParent(&app);
        ctx->setContextProperty("WorldClockHelper", worldClock);
    }

    // Whose permissions the Rust clients ask for, before any client asks.
    marathon::platform::set_app_id(appId.toStdString());
    marathon::platform::set_cache_dir(
        QStandardPaths::writableLocation(QStandardPaths::CacheLocation).toStdString());
    exposeClient<marathon::platform::Permissions>(ctx, "PermissionManager");

    // Lifecycle client is unconditional — any app might need to declare
    // an active background task. Whether the claim is accepted depends on
    // the manifest's backgroundCapabilities (gated shell-side), so it's
    // safe to expose without a permission probe.
    // Two names: "AppLifecycle" for code that uses the runner-friendly
    // alias, "AppLifecycleManager" for MApp and anything else that reaches
    // it through the MarathonOS.Shell singleton.
    ctx->setContextProperty("AppLifecycle",
                            exposeClient<marathon::platform::Lifecycle>(ctx, "AppLifecycleManager"));

    // Same singleton-mirror pattern as SettingsManagerCpp / Display /
    // Bluetooth below: apps compiled against the shell module see these
    // names as QML_SINGLETON in the qmlcache bytecode, so a bare
    // setContextProperty fails at runtime with "X was a singleton at
    // compile time, but is not a singleton anymore". Phone in particular
    // hits this immediately on PhoneApp.qml:14 (ContactsManager.contacts)
    // and the entire root never paints. Register both ways.
    if (hasPerm("contacts"))
        exposeClient<marathon::platform::Contacts>(ctx, "ContactsManager");
    if (hasPerm("telephony") || hasPerm("phone")) {
        exposeClient<marathon::platform::CallHistory>(ctx, "CallHistoryManager");
    }
    if (hasPerm("telephony") || hasPerm("phone"))
        exposeClient<marathon::platform::Telephony>(ctx, "TelephonyService");
    if (hasPerm("sms") || hasPerm("telephony"))
        exposeClient<marathon::platform::Sms>(ctx, "SMSService");

    // marathon-maild's client, made when the Mail app first reads it.
    qmlRegisterType<Captures>("MarathonOS.Services", 1, 0, "Captures");
    qmlRegisterSingletonType<MailService>("MarathonOS.Services", 1, 0, "MailService",
                                          [](QQmlEngine *, QJSEngine *) -> QObject * {
                                              auto *mail     = new MailService();
                                              auto *accounts = new MailList();
                                              auto *messages = new MailList();
                                              accounts->setParent(mail);
                                              messages->setParent(mail);
                                              mail->setModels(accounts, messages);
                                              return mail;
                                          });

    // The Music app's MPRIS player and album art.
    qmlRegisterType<marathon::platform::MprisPlayer>("MarathonOS.Music", 1, 0, "MprisPlayer");
    qmlRegisterSingletonType<marathon::platform::Artwork>("MarathonOS.Music", 1, 0, "Artwork",
                                                          [](QQmlEngine *, QJSEngine *) -> QObject * {
                                                              return new marathon::platform::Artwork();
                                                          });

    // The Maps app's routing and voice cues.
    qmlRegisterType<marathon::maps::Routing>("MarathonOS.Maps", 1, 0, "Routing");
    qmlRegisterType<marathon::maps::Voice>("MarathonOS.Maps", 1, 0, "Voice");

    // The Settings app's native types.
    qmlRegisterSingletonType<marathon::platform::AndroidApps>(
        "MarathonOS.Settings", 1, 0, "AndroidApps",
        [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::platform::AndroidApps(); });
    qmlRegisterSingletonType<marathon::platform::MmsSettings>(
        "MarathonOS.Settings", 1, 0, "MmsSettings",
        [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::platform::MmsSettings(); });
    qmlRegisterSingletonType<marathon::platform::KeyboardSettingsStore>(
        "MarathonOS.Settings", 1, 0, "KeyboardSettingsStore",
        [](QQmlEngine *, QJSEngine *) -> QObject * {
            return new marathon::platform::KeyboardSettingsStore();
        });
    qmlRegisterSingletonType<marathon::platform::SettingsController>(
        "MarathonOS.Settings", 1, 0, "SettingsController",
        [](QQmlEngine *, QJSEngine *) -> QObject * {
            auto *ctrl = new marathon::platform::SettingsController();
            if (QScreen *scr = QGuiApplication::primaryScreen()) {
                ctrl->initDisplay(
                    QStringLiteral("%1x%2").arg(scr->size().width()).arg(scr->size().height()),
                    QString::number(scr->refreshRate(), 'f', 0) + QStringLiteral(" Hz"),
                    QString::number(scr->physicalDotsPerInch(), 'f', 0) + QStringLiteral(" dpi"),
                    QString::number(scr->devicePixelRatio(), 'f', 2));
            }
            return ctrl;
        });
    qmlRegisterType<marathon::platform::StorageInfo>("MarathonOS.Settings", 1, 0, "StorageInfo");
    qmlRegisterType<marathon::platform::TimeZoneList>("MarathonOS.Settings", 1, 0, "TimeZoneList");

    // The Terminal app's VT engine and painter.
    qmlRegisterType<marathon::terminal::TerminalEngine>("MarathonOS.Terminal", 1, 0,
                                                        "TerminalEngine");
    qmlRegisterType<TerminalRenderer>("MarathonOS.Terminal", 1, 0, "TerminalRenderer");

    if (hasPerm("storage")) {
        exposeClient<marathon::platform::MediaLibrary>(ctx, "MediaLibraryManager");
        qmlRegisterSingletonType<marathon::platform::MusicLibrary>(
            "MarathonOS.Shell", 1, 0, "MusicLibraryManager",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::platform::MusicLibrary(); });
    }

    // Qt 6.10+ qmlcache compiles singleton lookups into bytecode at app build
    // time. Apps are built against the shell's MarathonOS.Shell module where
    // these names are QML_SINGLETON. When the runner loads compiled app QML,
    // setContextProperty alone fails with "X was a singleton at compile time,
    // but is not a singleton anymore" -- every singleton-style call throws
    // and onCompleted bails before tabs are created. Mirror the shell's
    // registration in the runner so the compiled-cache lookup resolves.
    marathon::platform::Settings *settingsClient = nullptr;
    if (hasPerm("system") || hasPerm("storage"))
        settingsClient = exposeClient<marathon::platform::Settings>(ctx, "SettingsManagerCpp");
    // Settings reads are unprivileged; MMotion needs reduceMotion in every app.
    if (settingsClient)
        ctx->setContextProperty("MarathonA11ySettings", settingsClient);
    else
        exposeClient<marathon::platform::Settings>(ctx, "MarathonA11ySettings", false);

    if (hasPerm("system"))
        exposeClient<marathon::platform::Wallpapers>(ctx, "WallpaperStore");
    if (hasPerm("system")) {
        exposeClient<marathon::platform::Bluetooth>(ctx, "BluetoothManagerCpp");
        exposeClient<marathon::platform::Security>(ctx, "SecurityManagerCpp");
        exposeClient<marathon::platform::Display>(ctx, "DisplayManagerCpp");
        exposeClient<marathon::platform::Power>(ctx, "PowerManagerService");
        auto *audio   = exposeClient<Audio>(ctx, "AudioManagerCpp");
        auto *streams = new AudioStreams();
        streams->setParent(audio);
        audio->setStreams(streams);
    }

    if (hasPerm("network")) {
        exposeClient<marathon::platform::Network>(ctx, "NetworkManagerCpp");
        exposeClient<marathon::platform::Modem>(ctx, "ModemManagerCpp", false);
    }

    ctx->setContextProperty(
        "NavigationRouter",
        exposeClient<marathon::platform::Navigation>(ctx, "NavigationService", false));
    exposeClient<marathon::platform::Haptics>(ctx, "HapticService");

    marathon::platform::Notifications *notifications = nullptr;
    if (hasPerm("notifications")) {
        notifications =
            exposeClient<marathon::platform::Notifications>(ctx, "NativeNotificationService", false);
        // Apps and the test suite consume this under the shorter name.
        ctx->setContextProperty("NotificationService", notifications);
    }
    if (hasPerm("sensors") || hasPerm("system"))
        exposeClient<marathon::platform::Sensors>(ctx, "SensorService", false);
    if (hasPerm("location"))
        exposeClient<marathon::platform::Location>(ctx, "LocationService", false);
    if (hasPerm("alarms") || hasPerm("system"))
        exposeClient<marathon::platform::Alarms>(ctx, "AlarmService", false);
    if (hasPerm("system"))
        exposeClient<marathon::platform::Updates>(ctx, "UpdateService", false);
    // The shell's Dav1 gates on "system"; with "storage" every app's client
    // was refused at launch.
    if (hasPerm("system"))
        exposeClient<marathon::platform::DavSync>(ctx, "DavSyncEngine", false);
    if (hasPerm("system")) {
        auto *installer =
            exposeClient<marathon::platform::AppInstaller>(ctx, "MarathonAppInstaller", false);
        QObject::connect(installer, &marathon::platform::AppInstaller::appRemoved, registry,
                         &AppRegistry::unregisterApp);
    }

    exposeClient<marathon::platform::SystemStatusStore>(ctx, "SystemStatusStore");
    exposeClient<marathon::platform::SystemControlStore>(ctx, "SystemControlStore");

    if (appId == "calendar")
        exposeClient<marathon::platform::Calendar>(ctx, "CalendarManager", false);
    registerPlatformTypes(ctx);

    const QString entryAbs      = QDir(appPath).filePath(entryPoint);
    const QUrl    entryUrl      = QUrl::fromLocalFile(entryAbs);
    const QString componentName = QFileInfo(entryPoint).completeBaseName();

    qInfo() << "[marathon-app-runner] Starting app" << appId << "entryPoint" << entryPoint
            << "entryAbs" << entryAbs << "appPath" << appPath;

    // qWarning: Release defines QT_NO_INFO_OUTPUT, which compiles qInfo out.
    if (logStartup) {
        qWarning().noquote() << "[startup]" << appId << "qml-setup" << startupTimer.elapsed()
                             << "ms";
        marathon::runner::log_startup(appId, "qml-setup", startupTimer.elapsed());
    }
    if (logStartup) {
        // One-shot: time from process entry to the first rendered frame —
        // the number a user perceives as "launch time".
        QObject::connect(&view, &QQuickWindow::frameSwapped, &view,
                         [&startupTimer, appId, fired = false]() mutable {
                             if (fired)
                                 return;
                             fired = true;
                             qWarning().noquote() << "[startup]" << appId << "first-frame"
                                                  << startupTimer.elapsed() << "ms";
                             marathon::runner::log_startup(appId, "first-frame", startupTimer.elapsed());
                         });
    }

    marathon::runner::RunnerLifecycle lifecycle;
    QPointer<QObject>                 appRoot;
    QObject::connect(&lifecycle, &marathon::runner::RunnerLifecycle::backRequested, &lifecycle,
                     [&]() { lifecycle.answer(invokeRoot(appRoot, "handleBack", "backPressed")); });
    QObject::connect(&lifecycle, &marathon::runner::RunnerLifecycle::forwardRequested, &lifecycle,
                     [&]() { lifecycle.answer(invokeRoot(appRoot, "handleForward", "forwardPressed")); });
    // Keel.Actions owns its name on Qt's session-bus connection.
    auto actionsReleased = std::make_shared<bool>(false);
    QObject::connect(&lifecycle, &marathon::runner::RunnerLifecycle::prepareFreezeRequested,
                     &lifecycle, [actionsReleased]() {
                         const QString name = qEnvironmentVariable("KEEL_ACTIONS_APP_ID");
                         if (!name.isEmpty())
                             *actionsReleased = QDBusConnection::sessionBus().unregisterService(name);
                     });
    QObject::connect(&lifecycle, &marathon::runner::RunnerLifecycle::thawed, &lifecycle,
                     [actionsReleased]() {
                         if (*actionsReleased)
                             *actionsReleased = !QDBusConnection::sessionBus().registerService(
                                 qEnvironmentVariable("KEEL_ACTIONS_APP_ID"));
                     });
    lifecycle.serve(appId);

    const QString appAbsPath = appPath;

    QTimer::singleShot(
        0, &view,
        [&view, engine, ctx, entryUrl, entryAbs, appId, componentName, appAbsPath, &lifecycle,
         &appRoot, &startupTimer, logStartup]() {
            QQmlComponent *component = nullptr;

            if (QFileInfo::exists(entryAbs)) {
                component = new QQmlComponent(engine, entryUrl, &view);
            } else {
                const QString wrapper =
                    marathon::runner::entry_wrapper(appAbsPath, appId, componentName);
                if (wrapper.isEmpty()) {
                    qCritical() << "[marathon-app-runner] Entry point file not found and no qmldir "
                                   "module found for"
                                << appId << "entryAbs=" << entryAbs;
                    QCoreApplication::exit(4);
                    return;
                }

                // A local URL loads synchronously: a Keel Actions call queued for
                // the app's bus name arrives only once its window is shown. Not
                // in the app's directory: a file URL imports its directory, and
                // the loose files there would shadow the app's module.
                component = new QQmlComponent(engine, &view);
                component->setData(wrapper.toUtf8(),
                                   QUrl::fromLocalFile(
                                       QStringLiteral("/marathon-app/%1/Wrapper.qml").arg(appId)));
            }

            auto createAndAttach = [component, &view, ctx, appId, &lifecycle, &appRoot,
                                    &startupTimer, logStartup]() {
                if (!component) {
                    QCoreApplication::exit(4);
                    return;
                }

                if (component->isError()) {
                    qCritical() << "[marathon-app-runner] QML component error for" << appId << ":"
                                << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                if (component->status() != QQmlComponent::Ready) {
                    qCritical() << "[marathon-app-runner] QML component not ready for" << appId
                                << "status=" << component->status()
                                << "errors=" << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                if (logStartup)
                    marathon::runner::log_startup(appId, "component-ready", startupTimer.elapsed());
                QObject *rootObj = component->create(ctx);
                if (!rootObj) {
                    qCritical() << "[marathon-app-runner] Failed to create app instance for"
                                << appId << ":" << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                auto *rootItem = qobject_cast<QQuickItem *>(rootObj);
                if (!rootItem) {
                    qCritical() << "[marathon-app-runner] App root is not a QQuickItem for"
                                << appId;
                    rootObj->deleteLater();
                    QCoreApplication::exit(4);
                    return;
                }

                rootItem->setParentItem(view.contentItem());
                rootItem->setWidth(view.width());
                rootItem->setHeight(view.height());

                // The root is a plain Item, so focusing it would take active
                // focus from the page and keys would never reach the page.
                if (!subtreeHasFocus(rootItem))
                    rootItem->forceActiveFocus();

                QObject::connect(&view, &QQuickView::widthChanged, rootItem,
                                 [&view, rootItem](int) { rootItem->setWidth(view.width()); });
                QObject::connect(&view, &QQuickView::heightChanged, rootItem,
                                 [&view, rootItem](int) { rootItem->setHeight(view.height()); });

                appRoot       = rootObj;
                const int sig = rootObj->metaObject()->indexOfSignal("minimizeRequested()");
                if (sig >= 0)
                    QObject::connect(rootObj, rootObj->metaObject()->method(sig), &lifecycle,
                                     lifecycle.metaObject()->method(
                                         lifecycle.metaObject()->indexOfMethod("minimizeRequested()")));

                if (logStartup)
                    marathon::runner::log_startup(appId, "created", startupTimer.elapsed());
                // Map only once the app's content exists: an earlier show() hands
                // the shell empty frames, which it reveals as a black window.
                view.show();
            };

            if (component->status() == QQmlComponent::Loading) {

                QObject::connect(component, &QQmlComponent::statusChanged, &view,
                                 [component, createAndAttach](QQmlComponent::Status st) {
                                     if (st == QQmlComponent::Ready || st == QQmlComponent::Error)
                                         createAndAttach();
                                 });
                return;
            }

            createAndAttach();
        });

    return QGuiApplication::exec();
}


