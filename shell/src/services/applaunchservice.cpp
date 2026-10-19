#include "applaunchservice.h"
#include "marathonapppaths.h"

#include "appmodel.h"
#include "processtree.h"
#include "sailfishlaunch.h"
#include "src/components/desktopfileparser.h"
#include "taskmodel.h"
#include "src/managers/deviceprofile.h"
#include "src/managers/screenmetrics.h"

#include <QMetaObject>
#include <QVariant>
#include <QDebug>
#include <QJSValue>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QJsonArray>
#include <QJsonDocument>
#include <QDateTime>
#include <QJsonObject>
#include <QSettings>
#include <QGuiApplication>
#include <QScreen>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusConnectionInterface>
#include <QDBusServiceWatcher>
#include <QUuid>

#if defined(HAVE_WAYLAND)
#include "wayland/waylandcompositor.h"
#include <QtWaylandCompositor/QWaylandClient>
#include <QtWaylandCompositor/QWaylandSurface>
#include <QtWaylandCompositor/QWaylandXdgSurface>
#include <QtWaylandCompositor/QWaylandXdgToplevel>
#include <utility>   // std::as_const
#endif

namespace {

// The DPI the shell's own Constants.scaleFactor uses.
qreal shellDpi() {
    const qreal dpi = ScreenMetrics::computeDpi(QGuiApplication::primaryScreen());
    return dpi > 0 ? dpi : 160.0;
}

// Function-local statics: compiled once on first use, with no pre-main
// initialiser that could throw uncatchably (which a namespace-scope
// QRegularExpression has).
const QRegularExpression &nonSlug() {
    static const QRegularExpression re{QStringLiteral("[^a-z0-9]+")};
    return re;
}

// The bwrap argument list is flattened into a single command string here and
// re-parsed with QProcess::splitCommand on the compositor side. That round
// trip silently loses two kinds of argument: one containing spaces (it splits
// into several) and, worse, an EMPTY one (it disappears entirely, shifting
// every argument after it by one position).
//
// The empty case broke every WebEngine app. The session exports
// MARATHON_LAYER_SAMPLES with an empty value, and qEnvironmentVariable's
// default only applies when a variable is UNSET, not when it is set-but-empty
// -- so `--setenv MARATHON_LAYER_SAMPLES ""` flattened to
// `--setenv MARATHON_LAYER_SAMPLES` and bwrap consumed the following
// `--setenv` as the value, then treated `MARATHON_GPU_HDR` as the program to
// exec: "bwrap: execvp MARATHON_GPU_HDR: No such file or directory".
// Browser and Maps both died there before showing a surface.
//
// splitCommand honours DOUBLE quotes only, so quote there and nowhere else.
// It cannot represent an EMPTY argument at all -- its tokenizer appends only
// non-empty tokens, so even a literal "" is dropped. Empty values therefore
// have to be prevented at the source: see envValue() below.
QString quoteForSplitCommand(const QString &arg) {
    if (arg.isEmpty())
        return QStringLiteral("\"\"");
    if (!arg.contains(QLatin1Char(' ')) && !arg.contains(QLatin1Char('"')))
        return arg;
    QString escaped = arg;
    escaped.replace(QLatin1Char('"'), QLatin1String("\\\""));
    return QLatin1Char('"') + escaped + QLatin1Char('"');
}

// qEnvironmentVariable's fallback applies only when a variable is UNSET. The
// session exports several of these EMPTY, and an empty value cannot survive
// the command-string round trip (above) -- it vanishes and shifts every later
// argument, which is what made bwrap exec a variable name. Treat empty as
// absent.
QString envValue(const char *name, const QString &fallback) {
    const QString v = qEnvironmentVariable(name);
    return v.isEmpty() ? fallback : v;
}

// Mounts the app's own security-context socket where WAYLAND_DISPLAY points,
// over the shell's unrestricted one, and hides every sandbox's socket so an
// app cannot connect as another. Must follow the XDG_RUNTIME_DIR bind.
QStringList waylandSocketArgs(const QString &socket, const QString &runtimeDir) {
    const QString display =
        qEnvironmentVariable("MARATHON_WL_SOCKET_NAME", QStringLiteral("marathon-wayland-0"));
    return {QStringLiteral("--ro-bind"), socket, runtimeDir + QLatin1Char('/') + display,
            QStringLiteral("--tmpfs"), QFileInfo(socket).path()};
}

QString newSandboxInstance() {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QString joinForSplitCommand(const QStringList &args) {
    QStringList quoted;
    quoted.reserve(args.size());
    for (const QString &a : args)
        quoted << quoteForSplitCommand(a);
    return quoted.join(QLatin1Char(' '));
}
    // QtWebEngine's bundled Chromium on Alpine is built WITHOUT the wayland
    // ozone backend; passing --ozone-platform=wayland or --enable-features=
    // UseOzonePlatform crashes the render process with FATAL "Invalid ozone
    // platform: wayland" (Browser + Maps, observed 2026-06-25). Qt WebEngine
    // renders into a Qt-side GL texture and Qt handles wayland presentation,
    // so Chromium itself doesn't need a wayland ozone — let it pick its
    // built-in default.
    //
    // The i.MX 8M Quad GC7000Lite (etnaviv) on the Librem 5 only exposes
    // partial GLES3 — Chromium probes for ES3 to set up WebGL2 and aborts
    // the GPU command-buffer with kFatalFailure "ES3 is blocklisted/disabled/
    // unsupported by driver" (observed 2026-06-25 Maps + Browser viewport).
    // Drop ANGLE (which insists on ES3) in favour of native EGL/GLES2, and
    // explicitly disable WebGL2 so the renderer doesn't try to set up
    // an ES3 context at all.
    //
    // WebGL 1.0 is intentionally left enabled. It maps to GLES2 + GLSL ES
    // 1.0 which etnaviv DOES expose (verified on r234 device 2026-06-26
    // via `eglinfo`: "OpenGL ES profile version: OpenGL ES 2.0 Mesa
    // 26.1.1 ... GLSL ES 1.0.16"). Killing WebGL globally was the previous
    // policy but it black-holed Maps (MapLibre GL JS is WebGL-only — no
    // canvas2D fallback for vector tiles; the viewport stays at the
    // marathon-dark background colour with no tiles ever painting). The
    // ES3 abort that motivated the original disable is a WebGL2 probe
    // failure, not WebGL1 — so keeping WebGL2 disabled is sufficient.
    //
    // Per-app overrides via the manifest `chromiumFlags` string field
    // still take precedence if a future app needs a different shape.
    //
    // 2026-06-26 update — what we ship now and why:
    //
    // After full research (see docs/RESEARCH_QTWEBENGINE_ETNAVIV.md):
    //
    // 1. Mesa's etnaviv driver on the GC7000Lite is still GLES 2.0 only —
    //    GLES 3 work by Christian Gmeiner is in flight but not landed
    //    as of Mesa 26.1.x (2026-06).
    //
    // 2. QtWebEngine ≥ 6.9 (Chromium 130) tightened its Linux GL allowlist:
    //    native EGL/GLES (which is all etnaviv can produce) is no longer
    //    in the allowlist. NXP's own i.MX 8M Plus BSP engineer hit the
    //    exact same eglCreateContext "Requested version is not supported"
    //    on the Qt forum thread "i.MX8MP NXP BSP 6.6.3 with QtWebEngine
    //    6.9.1 and Chromium 130.0.6723.192" — no fix posted.
    //
    // 3. `--use-gl=angle` triggers "unsupported SceneGraph Backend" because
    //    Linux Qt SceneGraph has no ANGLE backend at all.
    //
    // 4. `MESA_GLES_VERSION_OVERRIDE=2.0` only changes glGetString output;
    //    it does NOT clamp the eglCreateContext attribute list Chromium
    //    asks for. Cargo-cult flag.
    //
    // Alpine's qt6-qtwebengine is built WITHOUT ANGLE on aarch64
    // (verified 2026-06-26: `strings QtWebEngineProcess | grep -c
    // ANGLE` returns 0). So `--use-gl=angle` is a no-op on this build
    // — the only working chromium GL backend is native EGL.
    //
    // The actual error on launch is:
    //   "EGL Driver message (Error) eglCreateContext: Requested version
    //    is not supported"
    // — etnaviv (GC7000Lite) exposes GLES 2.0 only, and Chromium 130 by
    // default asks eglCreateContext for a GLES 3.x context.
    // `--disable-es3-gl-context` + `--disable-es3-apis` is the chromium
    // command-line knob that drops the GLES3 request down to GLES2.
    // That's the actually-correct flag combination for this hardware,
    // not the ANGLE/SwiftShader/software paths I shipped earlier.
    //
    // `--use-cmd-decoder=passthrough` tells chromium to use the
    // passthrough command decoder instead of the validating one — the
    // passthrough decoder is what mobile GL drivers (including
    // etnaviv) are tested against. It's also what ChromeOS uses.
    //
    // Chromium's own sandbox stays on: its namespace layer nests inside our
    // bwrap and its renderers run under seccomp-bpf (docs/SECURITY_MODEL.md).
    // `--disable-dev-shm-usage` because /dev/shm in the bwrap tmpfs is
    // small and chromium SIGTRAPs when it runs out.
    // `--in-process-gpu` keeps GPU init in the runner's address space
    // where Qt already wired EGL — avoids a second namespace clone.
    //
    // WebGL2 disabled — needs GLES3. WebGL1 stays enabled (works on
    // GLES2). Vulkan disabled — etnaviv has no Vulkan ICD.
    constexpr const char *kDefaultChromiumFlags =
        // SW raster baseline with full HW-accel infrastructure prepped
        // underneath. Six companion fixes are all in place:
        //   1. bwrap exposes only /dev/dri/renderD128 (no card1 master).
        //   2. bwrap explicit binds for /sys/dev/char, /sys/class/drm,
        //      /sys/devices for Mesa's DRM device-discovery symlink walk.
        //   3. MESA_LOADER_DRIVER_OVERRIDE=etnaviv hard-set on runner env.
        //   4. marathon-shell-session exports
        //      QT_WAYLAND_HARDWARE_INTEGRATION="wayland-egl;linux-dmabuf-
        //      unstable-v1" so the compositor's dmabuf plugin loads
        //      (verified live via wayland-info — was completely absent
        //      before).
        //   5. marathon-app-runner main() calls
        //      QSurfaceFormat::setDefaultFormat() with
        //      setRenderableType(OpenGLES) AFTER
        //      QtWebEngineQuick::initialize() and BEFORE
        //      QGuiApplication so Qt's RHI probe asks for an ES2 context
        //      that etnaviv can satisfy.
        //   6. EGL_PLATFORM=wayland pins Mesa's platform discovery.
        // Despite all of the above, Chromium 130's GPU process makes its
        // OWN eglCreateContext call requesting an ES 3.x config that
        // etnaviv (HALTI0, GLES2-only) rejects with __DRI_CTX_ERROR_
        // BAD_VERSION → EGL_BAD_MATCH. Setting Qt's defaultFormat
        // doesn't affect Chromium's separate GPU thread — it has its
        // own GL implementation negotiation. The final gap requires
        // either patching qt6-qtwebengine's bundled Chromium GL init,
        // waiting for Mesa 26.2+ etnaviv GLES3, or migrating to WPE
        // WebKit. Until then, --use-gl=disabled is the working baseline
        // and the infrastructure above is ready to flip to --use-gl=egl
        // the moment Chromium accepts.
        // Web canvas via SW raster. Empirically validated across this
        // session, --use-gl=disabled is the ONLY value Alpine's
        // qt6-qtwebengine accepts that actually renders content:
        //   - egl       → fails EGL_BAD_MATCH at eglCreateContext
        //                 (Chromium 130 GPU process requests ES3.x,
        //                 etnaviv ES2-only). Marathon's UI still
        //                 renders fine via Qt RHI + v4 dmabuf; only
        //                 the web canvas comes back black.
        //   - swiftshader → "not supported with the current
        //                 configuration" — Alpine's qtwebengine
        //                 build has no SwiftShader linked.
        //   - angle     → no ANGLE compiled into Alpine qtwebengine.
        // SW raster on 4 Cortex-A53 cores is ~5-15fps depending on
        // page complexity. Marathon's UI + browser chrome are
        // HW-accel via Qt RHI + the v4 dmabuf protocol Marathon
        // implements in shell/src/wayland/linuxdmabufv1.* so the
        // perceived perf budget is mostly preserved.
        // When EITHER Mesa 26.2 etnaviv GLES3 lands OR qt6-qtwebengine
        // gets a build with ANGLE-GLES, flip to --use-gl=egl here.
        // All the supporting infrastructure (bwrap-only-renderD128,
        // Mesa env, dmabuf v4, runner setDefaultFormat) is already
        // in place for that one-line flip.
        "--use-gl=disabled "
        "--disable-gpu "
        "--ignore-gpu-blocklist "
        "--disable-dev-shm-usage "
        // WebGL kept enabled: the comment at the top of this block
        // promised "WebGL1 stays enabled (works on GLES2)" but the
        // disable-features list was banning both versions, leaving
        // Maps's MapLibre GL JS unable to initialize and rendering
        // a blank map canvas. Chromium's SW WebGL path (Skia/Ganesh
        // CPU pipeline) handles WebGL1 even with --use-gl=disabled;
        // it just hands the texture upload back through the dmabuf
        // path that Marathon already wires for the rest of the
        // WebEngine surface. WebGL2 stays disabled — needs GLES3
        // which etnaviv (HALTI0) doesn't expose.
        "--disable-features=Vulkan,UseSkiaRenderer,WebGL2 "
        "--num-raster-threads=2 "
        "--enable-viewport "
        "--main-frame-resizes-are-orientation-changes";

    // Stacks whose GL Chromium can drive, so WebGL runs on the GPU. ANGLE
    // over GLES: QtWebEngine's own pick draws page content black on V3D.
    constexpr const char *kGpuChromiumFlags = "--use-gl=angle --use-angle=gles "
                                              "--ignore-gpu-blocklist "
                                              "--disable-dev-shm-usage "
                                              "--num-raster-threads=2 "
                                              "--enable-viewport "
                                              "--main-frame-resizes-are-orientation-changes";

    QStringList storageBinds(const QString &homeDir) {
        QStringList args;
        const QString dcim = homeDir + QStringLiteral("/DCIM");
        const QStringList folders = AppLaunchService::sharedFolders();
        for (const QString &dir : folders) {
            if (dir == dcim) {
                args << QStringLiteral("--bind-try") << dir << dir;
                continue;
            }
            QDir().mkpath(dir);
            args << QStringLiteral("--bind") << dir << dir;
        }
        // MediaLibraryManager::getThumbnailsDir(), which runs in this process.
        const QString thumbs = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
            QStringLiteral("/marathon/thumbnails");
        QDir().mkpath(thumbs);
        args << QStringLiteral("--ro-bind") << thumbs << thumbs;
        return args;
    }

    const char *deviceChromiumFlags() {
        const bool gpu = DeviceProfile::instance().gpuStack() == QLatin1String("mesa-v3d");
        return gpu ? kGpuChromiumFlags : kDefaultChromiumFlags;
    }
}

AppLaunchService::AppLaunchService(AppModel *appModel, TaskModel *taskModel, QObject *parent)
    : QObject(parent)
    , m_spareCount(DeviceProfile::instance().runnerPool())
    , m_appModel(appModel)
    , m_taskModel(taskModel) {
    if (m_taskModel) {
        connect(m_taskModel, &TaskModel::taskLaunched, this, [this]() {
            for (auto it = m_secureApps.begin(); it != m_secureApps.end(); ++it)
                it.value() = it.value() || m_taskModel->getTaskByAppId(it.key());
        });
        connect(m_taskModel, &TaskModel::taskClosed, this, [this]() {
            const qsizetype before = m_secureApps.size();
            m_secureApps.removeIf([this](const QHash<QString, bool>::iterator it) {
                return it.value() && !m_taskModel->getTaskByAppId(it.key());
            });
            if (m_secureApps.size() != before)
                emit secureAppsChanged();
        });
    }
    // First spare spawns after shell boot settles; adopts refill on demand.
    QTimer::singleShot(8000, this, &AppLaunchService::refillSpares);
}

void AppLaunchService::setCompositor(QObject *obj) {
    if (m_compositor == obj)
        return;

    if (m_compositor)
        QObject::disconnect(m_compositor, nullptr, this, nullptr);

    m_compositor = obj;

    if (m_compositor) {
#if defined(HAVE_WAYLAND)
        if (auto *wc = qobject_cast<WaylandCompositor *>(m_compositor.data())) {
            wc->setSecureApps(secureApps());
            QObject::connect(this, &AppLaunchService::secureAppsChanged, wc,
                             [this, wc]() { wc->setSecureApps(secureApps()); });
            QObject::connect(wc, &WaylandCompositor::appLaunched, this,
                             [this](const QString &command, qint64 pid) {
                                 onCompositorAppLaunched(command, pid);
                             });
            QObject::connect(wc, &WaylandCompositor::appClosed, this,
                             [this](qint64 pid) { onCompositorAppClosed(pid); });
            QObject::connect(wc, &WaylandCompositor::nativeBackUnhandled, this,
                             &AppLaunchService::nativeBackUnhandled);
            QObject::connect(
                wc, &WaylandCompositor::surfaceCreated, this,
                [this](QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface) {
                    onCompositorSurfaceCreated(surface, surfaceId, xdgSurface);
                });
            QObject::connect(wc, &WaylandCompositor::surfaceDestroyed, this,
                             [this](QWaylandSurface *, int surfaceId) {
                                 onWindowDestroyed(surfaceId);
                             });
            QObject::connect(wc, &WaylandCompositor::surfaceActivated, this,
                             [this](QWaylandSurface *, int surfaceId,
                                    QWaylandXdgSurface *xdgSurface, qint64 launchPid) {
                                 onCompositorSurfaceActivated(surfaceId, xdgSurface, launchPid);
                             });
            QObject::connect(
                wc, &WaylandCompositor::dialogCreated, this,
                [this](QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface) {
                    const qint64 pid   = surface->client()->processId();
                    QString      appId = sandboxAppIdFor(surface);
                    if (appId.isEmpty())
                        appId = appIdForPid(pid);
                    // A hosted app (marathon-keel-host) runs as the registered
                    // process's child.
                    for (auto it = m_pidToAppId.cbegin(); appId.isEmpty() && it != m_pidToAppId.cend(); ++it) {
                        if (isDescendantPid(pid, it.key()))
                            appId = it.value();
                    }
                    // Only an app the shell runs may put a window over others.
                    if (appId.isEmpty()) {
                        qWarning() << "[AppLaunchService] Dialog surfaceId" << surfaceId
                                   << "from PID" << pid << "of no app - not shown";
                        return;
                    }
                    qInfo() << "[AppLaunchService] Dialog surfaceId" << surfaceId << "for"
                            << appId;
                    emit dialogSurfaceCreated(appId, xdgSurface, surfaceId);
                });
        }
#endif
    }

    emit compositorChanged();
}

void AppLaunchService::setAppWindow(QObject *obj) {
    if (m_appWindow == obj)
        return;
    m_appWindow = obj;
    emit appWindowChanged();
}

void AppLaunchService::setUiStore(QObject *obj) {
    if (m_uiStore == obj)
        return;
    m_uiStore = obj;
    emit uiStoreChanged();
}

void AppLaunchService::setAppLifecycleManager(QObject *obj) {
    if (m_appLifecycleManager == obj)
        return;
    m_appLifecycleManager = obj;
    emit appLifecycleManagerChanged();
}

bool AppLaunchService::isAppLaunching(const QString &appId) const {
    return m_launchingApps.contains(appId);
}

void AppLaunchService::closeNativeApp(int surfaceId) {
    QObject *comp = m_compositor.data();
    if (!comp) {
        qWarning() << "[AppLaunchService] Cannot close native app - compositor not available";
        return;
    }
    const bool ok =
        QMetaObject::invokeMethod(comp, "closeWindow", Qt::DirectConnection, Q_ARG(int, surfaceId));
    if (!ok)
        qWarning() << "[AppLaunchService] Failed to invoke closeWindow(int) on compositor";
}

bool AppLaunchService::canLaunch(const QString &appId) const {
    return !resolveAppObject(appId).isEmpty();
}

QStringList AppLaunchService::sharedFolders() {
    const QString home = QDir::homePath();
    QStringList   dirs;
    for (const auto loc : {QStandardPaths::PicturesLocation, QStandardPaths::MusicLocation,
                           QStandardPaths::MoviesLocation, QStandardPaths::DocumentsLocation,
                           QStandardPaths::DownloadLocation}) {
        const QString dir = QStandardPaths::writableLocation(loc);
        if (!dir.isEmpty() && dir != home)
            dirs << dir;
    }
    dirs << home + QStringLiteral("/DCIM");
    return dirs;
}

QVariantMap AppLaunchService::resolveAppObject(const QVariant &app) const {
    if (app.typeId() == QMetaType::QVariantMap) {
        QVariantMap   out   = app.toMap();
        const QString appId = out.value("id").toString();
        if (!appId.isEmpty() && m_appModel) {
            if (App *a = m_appModel->getApp(appId)) {
                if (out.value("name").toString().isEmpty())
                    out["name"] = a->name();
                if (out.value("icon").toString().isEmpty())
                    out["icon"] = a->icon();
                if (out.value("type").toString().isEmpty())
                    out["type"] = a->type();
                if (out.value("exec").toString().isEmpty())
                    out["exec"] = a->exec();
                if (out.value("permissions").toStringList().isEmpty())
                    out["permissions"] = a->permissions();
            }
        }
        return out;
    }

    if (app.userType() == qMetaTypeId<QJSValue>()) {
        const QJSValue v = app.value<QJSValue>();
        if (v.isString()) {
            return resolveAppObject(v.toString());
        }
        if (v.isObject()) {
            const QVariant    asVariant = v.toVariant();
            const QVariantMap asMap     = asVariant.toMap();
            return resolveAppObject(asMap);
        }
        return {};
    }

    if (app.typeId() == QMetaType::QString) {
        const QString appId = app.toString();
        if (App *a = m_appModel ? m_appModel->getApp(appId) : nullptr) {
            return {
                {"id", a->id()},     {"name", a->name()}, {"icon", a->icon()},
                {"type", a->type()}, {"exec", a->exec()}, {"permissions", a->permissions()},
            };
        }

        if (m_taskModel) {
            if (Task *t = m_taskModel->getTaskByAppId(appId)) {
                return {
                    {"id", appId},
                    {"name", t->title().isEmpty() ? appId : t->title()},
                    {"icon", t->icon()},
                    {"type", t->appType().isEmpty() ? QStringLiteral("native") : t->appType()},
                    {"exec", QString()},
                };
            }
        }

        // An entry kept off the grid (Waydroid's NoDisplay stock Android
        // apps) still launches by its id.
        const QString entry = QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                                     appId + QStringLiteral(".desktop"));
        if (!entry.isEmpty())
            return DesktopFileParser().parseDesktopFile(entry, true);

        return {};
    }

    if (QObject *obj = app.value<QObject *>()) {
        QVariantMap   out;
        const QString appId = obj->property("id").toString();
        out["id"]           = appId;
        out["name"]         = obj->property("name");
        out["icon"]         = obj->property("icon");
        out["type"]         = obj->property("type");
        out["exec"]         = obj->property("exec");

        // Permissions: a QML object literal's `permissions` property arrives
        // as QVariantList (JS array), not QStringList. Convert explicitly so
        // downstream `toStringList()` doesn't return empty and reinstate
        // --unshare-net on an app that legitimately declared 'network'.
        const QVariant rawPerms = obj->property("permissions");
        QStringList    perms;
        if (rawPerms.canConvert<QStringList>()) {
            perms = rawPerms.toStringList();
        } else if (rawPerms.canConvert<QVariantList>()) {
            const auto permEntries = rawPerms.toList();
            for (const QVariant &v : permEntries)
                perms << v.toString();
        }

        if (!appId.isEmpty() && m_appModel) {
            if (App *a = m_appModel->getApp(appId)) {
                if (out.value("name").toString().isEmpty())
                    out["name"] = a->name();
                if (out.value("icon").toString().isEmpty())
                    out["icon"] = a->icon();
                if (out.value("type").toString().isEmpty())
                    out["type"] = a->type();
                if (out.value("exec").toString().isEmpty())
                    out["exec"] = a->exec();
                if (perms.isEmpty())
                    perms = a->permissions();
            }
        }
        out["permissions"] = perms;

        if (!out.value("id").isValid() || out.value("name").toString().isEmpty())
            return {};
        return out;
    }

    return {};
}

bool AppLaunchService::launchAppWithRoute(const QVariant &app, const QString &route,
                                          const QString &paramsJson, QObject *compositorRef,
                                          QObject *appWindowRef) {
    m_pendingRoute           = route;
    m_pendingRouteParamsJson = paramsJson;
    const bool ok            = launchApp(app, compositorRef, appWindowRef);
    // Clear if launch failed; on success launchMarathonApp clears them itself.
    if (!ok) {
        m_pendingRoute.clear();
        m_pendingRouteParamsJson.clear();
    }
    return ok;
}

bool AppLaunchService::startAppInBackground(const QVariant &app) {
    const QString appId = resolveAppObject(app).value("id").toString();
    if (!appId.isEmpty() &&
        (pidForAppId(appId) > 0 || m_launchingApps.contains(appId) ||
         (m_taskModel && m_taskModel->getTaskByAppId(appId)))) {
        if (m_appLifecycleManager)
            QMetaObject::invokeMethod(m_appLifecycleManager, "wakeApp", Qt::DirectConnection,
                                      Q_ARG(QString, appId));
        return true;
    }
    m_backgroundLaunches.insert(appId);
    m_startingInBackground = true;
    const bool ok          = launchApp(app, nullptr, nullptr);
    m_startingInBackground = false;
    if (!ok)
        m_backgroundLaunches.remove(appId);
    return ok;
}

bool AppLaunchService::launchApp(const QVariant &app, QObject *compositorRef,
                                 QObject *appWindowRef) {
    QObject          *comp = compositorRef ? compositorRef : m_compositor.data();
    QObject          *win  = appWindowRef ? appWindowRef : m_appWindow.data();

    const QVariantMap appObj = resolveAppObject(app);
    const QString     appId  = appObj.value("id").toString();
    const QString     name   = appObj.value("name").toString();
    const QString     type   = appObj.value("type").toString();

    if (!win) {
        qWarning() << "[AppLaunchService] appWindow not available";
        emit appLaunchFailed(appId, name, "No app window reference");
        return false;
    }
    if (appId.isEmpty() || name.isEmpty()) {
        // Surface the input type + the partial resolution so the
        // next reproduction tells us whether the bad variant came
        // from a QString id (AppModel cache miss), a QML object
        // literal (missing name property), or a stale QVariantMap.
        qWarning() << "[AppLaunchService] Invalid app object — appId:" << appId << "name:" << name
                   << "type:" << type << "inputType:" << app.typeName()
                   << "resolved keys:" << appObj.keys();
        emit appLaunchFailed(appId, name, "Invalid app object");
        return false;
    }
    // The launch-hold guards against duplicate SPAWNS. An app that already
    // has a surface is a re-show, not a spawn — blocking it here left the
    // app window open on its bare root (restore within the hold window).
    Task      *heldTask = m_taskModel ? m_taskModel->getTaskByAppId(appId) : nullptr;
    const bool hasUsableSurface =
        heldTask && heldTask->surfaceId() >= 0 && heldTask->waylandSurface();
    // Still starting in the background: show it as it maps, not a second copy.
    if (!m_startingInBackground && m_backgroundLaunches.remove(appId) && !hasUsableSurface) {
        qInfo() << "[AppLaunchService] Foregrounding background launch:" << appId;
        if (m_uiStore)
            invokeVoid(m_uiStore, "openApp", {appId, name, appObj.value("icon")});
        invokeVoid(win, "show",
                   {appId, name, appObj.value("icon"),
                    type.isEmpty() ? QStringLiteral("marathon") : type, QVariant(), -1});
        if (!m_pendingRoute.isEmpty())
            emit routeForRunningApp(appId, m_pendingRoute, m_pendingRouteParamsJson);
        m_pendingRoute.clear();
        m_pendingRouteParamsJson.clear();
        emit appLaunchCompleted(appId, name);
        return true;
    }
    if (m_launchingApps.contains(appId) && !hasUsableSurface) {
        qWarning() << "[AppLaunchService] App already launching:" << appId;
        return false;
    }

    // Already running with a surface: bring it forward rather than spawn.
    // This sat in launchMarathonApp only, so native apps and flatpaks always
    // re-spawned; a single-instance app then handed off to its running copy,
    // no new surface ever arrived, and the launch timed out.
    if (hasUsableSurface) {
        qInfo() << "[AppLaunchService] Restoring running app:" << appId << "surfaceId"
                << heldTask->surfaceId() << "type" << heldTask->appType();
        if (m_uiStore)
            invokeVoid(m_uiStore, "restoreApp", {appId, name, appObj.value("icon")});
        invokeVoid(win, "show",
                   {appId, name, appObj.value("icon"), heldTask->appType(),
                    QVariant::fromValue(heldTask->waylandSurface()), heldTask->surfaceId()});
        if (!m_pendingRoute.isEmpty())
            emit routeForRunningApp(appId, m_pendingRoute, m_pendingRouteParamsJson);
        m_pendingRoute.clear();
        m_pendingRouteParamsJson.clear();
        m_launchingApps.remove(appId);
        emit appLaunchCompleted(appId, name);
        return true;
    }

    m_launchingApps.insert(appId);
    emit appLaunchStarted(appId, name);

    // Still running, without a window: a second instance would only hand off
    // to it and exit, so ask the running one for a window.
    if ((type == "native" || type == "flatpak") && pidForAppId(appId) > 0 &&
        appId.contains(QLatin1Char('.'))) {
        activateRunningApp(appObj, comp, win);
        return true;
    }

    // A flatpak is a native Wayland client too; the compositor's launchApp
    // recognises its FLATPAK: exec and adds the socket arguments.
    if (type == "native" || type == "flatpak")
        return launchNativeApp(appObj, comp, win);
    return launchMarathonApp(appObj, comp, win);
}

bool AppLaunchService::launchNativeApp(const QVariantMap &app, QObject *compositorRef,
                                       QObject *appWindowRef) {
    const QString appId = app.value("id").toString();
    const QString name  = app.value("name").toString();
    const QString icon  = app.value("icon").toString();
    const QString exec  = app.value("exec").toString();

    if (!compositorRef) {
        m_launchingApps.remove(appId);
        emit appLaunchFailed(appId, name, "Compositor not available");
        return false;
    }

    if (!m_backgroundLaunches.contains(appId)) {
        if (m_uiStore)
            invokeVoid(m_uiStore, "openApp", {appId, name, icon});
        invokeVoid(appWindowRef, "show",
                   {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
    }
    emit appLaunchProgress(appId, 50);

    if (!exec.isEmpty()) {
        PendingLaunch p;
        p.appId   = appId;
        p.name    = name;
        p.icon    = icon;
        p.type    = QStringLiteral("native");
        p.command = exec;
        m_pendingByCommand.insert(exec, p);

        QPointer<QObject> comp(compositorRef);
        const auto        spawn = [comp, exec]() {
            if (!comp || !QMetaObject::invokeMethod(comp, "launchApp", Qt::DirectConnection,
                                                    Q_ARG(QString, exec)))
                qWarning() << "[AppLaunchService] Failed to invoke launchApp(QString) on compositor";
        };
        if (exec.startsWith(QLatin1String("waydroid app "))) {
            if (m_appLifecycleManager)
                QMetaObject::invokeMethod(m_appLifecycleManager, "wakeApp", Qt::DirectConnection,
                                          Q_ARG(QString, appId));
            startAndroidSession(spawn);
        } else {
            spawn();
        }
    }

    m_launchingApps.remove(appId);
    emit appLaunchCompleted(appId, name);
    return true;
}

// `waydroid app launch` with no session running becomes the session, and
// Android stops with it; the session unit runs it instead. Without the unit,
// or if no session comes in a minute, the launcher runs regardless.
void AppLaunchService::startAndroidSession(const std::function<void()> &then) {
    QDBusConnection bus     = QDBusConnection::sessionBus();
    const QString   session = QStringLiteral("id.waydro.Session");
    if (!bus.isConnected()) {
        then();
        return;
    }
    if (bus.interface()->isServiceRegistered(session)) {
        waitForAndroidBoot(then);
        return;
    }
    auto *wait    = new QObject(this);
    auto  done    = [this, wait, then]() {
        if (wait->property("done").toBool())
            return;
        wait->setProperty("done", true);
        wait->deleteLater();
        waitForAndroidBoot(then);
    };
    auto *watcher = new QDBusServiceWatcher(session, bus, QDBusServiceWatcher::WatchForRegistration,
                                            wait);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, wait, done);
    QTimer::singleShot(60000, wait, done);
    QDBusMessage start = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
        QStringLiteral("org.freedesktop.systemd1.Manager"), QStringLiteral("StartUnit"));
    start << QStringLiteral("marathon-waydroid.service") << QStringLiteral("replace");
    auto *call = new QDBusPendingCallWatcher(bus.asyncCall(start), wait);
    connect(call, &QDBusPendingCallWatcher::finished, wait, [done](QDBusPendingCallWatcher *w) {
        if (w->isError()) {
            qInfo() << "[AppLaunchService] Android session unit not started:"
                    << w->error().message();
            done();
        }
    });
}

// The session comes at container start, Android about ten seconds later, and
// a `waydroid app launch` before that is dropped. deckardd says when Android
// runs (Deckard1 GetRuntime / RuntimeChanged); without deckardd, or after
// 90 s, the launch goes regardless.
void AppLaunchService::waitForAndroidBoot(const std::function<void()> &then) {
    QDBusConnection bus     = QDBusConnection::sessionBus();
    const QString   service = QStringLiteral("org.marathonos.Deckard");
    if (!bus.interface()->isServiceRegistered(service)) {
        then();
        return;
    }
    m_afterAndroidBoot << then;
    if (m_afterAndroidBoot.size() > 1)
        return;
    emit androidStartingChanged();
    const QString path  = QStringLiteral("/org/marathonos/Deckard");
    const QString iface = QStringLiteral("org.marathonos.Deckard1");
    bus.connect(service, path, iface, QStringLiteral("RuntimeChanged"), this,
                SLOT(onAndroidRuntimeChanged(QVariantMap)));
    auto *call = new QDBusPendingCallWatcher(
        bus.asyncCall(QDBusMessage::createMethodCall(service, path, iface, QStringLiteral("GetRuntime"))),
        this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isError())
            androidBooted();
        else
            onAndroidRuntimeChanged(reply.value());
    });
    QTimer::singleShot(90000, this, &AppLaunchService::androidBooted);
}

void AppLaunchService::onAndroidRuntimeChanged(const QVariantMap &runtime) {
    if (runtime.value(QStringLiteral("state")).toString() == QLatin1String("running"))
        androidBooted();
}

void AppLaunchService::androidBooted() {
    if (m_afterAndroidBoot.isEmpty())
        return;
    QDBusConnection::sessionBus().disconnect(
        QStringLiteral("org.marathonos.Deckard"), QStringLiteral("/org/marathonos/Deckard"),
        QStringLiteral("org.marathonos.Deckard1"), QStringLiteral("RuntimeChanged"), this,
        SLOT(onAndroidRuntimeChanged(QVariantMap)));
    const QList<std::function<void()>> waiting = std::exchange(m_afterAndroidBoot, {});
    emit androidStartingChanged();
    for (const auto &launch : waiting)
        launch();
}

// org.freedesktop.Application on the desktop id: a DBusActivatable app owns
// that name, and GApplication and KDBusService serve the interface either
// way. Anything else (no owner, no interface) starts the app as before.
void AppLaunchService::activateRunningApp(const QVariantMap &app, QObject *compositorRef,
                                          QObject *appWindowRef) {
    const QString appId = app.value("id").toString();
    if (m_appLifecycleManager)
        QMetaObject::invokeMethod(m_appLifecycleManager, "wakeApp", Qt::DirectConnection,
                                  Q_ARG(QString, appId));
    QString path = QLatin1Char('/') + appId;
    path.replace(QLatin1Char('.'), QLatin1Char('/')).replace(QLatin1Char('-'), QLatin1Char('_'));
    QDBusMessage msg = QDBusMessage::createMethodCall(
        appId, path, QStringLiteral("org.freedesktop.Application"), QStringLiteral("Activate"));
    msg << QVariantMap();
    msg.setAutoStartService(false);

    QPointer<QObject> comp(compositorRef);
    QPointer<QObject> win(appWindowRef);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, app, appId, comp, win](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (w->isError()) {
                    qInfo() << "[AppLaunchService] Activate" << appId
                            << "failed:" << w->error().message() << "- starting it";
                    launchNativeApp(app, comp, win);
                    return;
                }
                qInfo() << "[AppLaunchService] Activated running app" << appId;
                const QString name = app.value("name").toString();
                const QString icon = app.value("icon").toString();
                if (m_uiStore)
                    invokeVoid(m_uiStore, "openApp", {appId, name, icon});
                if (win)
                    invokeVoid(win, "show",
                               {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
                m_launchingApps.remove(appId);
                emit appLaunchCompleted(appId, name);
            });
}

bool AppLaunchService::launchMarathonApp(const QVariantMap &app, QObject *, QObject *appWindowRef) {
    const QString appId = app.value("id").toString();
    const QString name  = app.value("name").toString();
    const QString icon  = app.value("icon").toString();
    const QString type  = app.value("type").toString();

    QObject      *comp = m_compositor.data();
    if (!comp) {
        m_launchingApps.remove(appId);
        emit appLaunchFailed(appId, name, "Compositor not available");
        return false;
    }

    // launchApp() has already restored any task with a usable surface.
    if (m_taskModel) {
        if (Task *existing = m_taskModel->getTaskByAppId(appId))
            qWarning() << "[AppLaunchService] Task without usable surface for" << appId
                       << "- surfaceId" << existing->surfaceId() << "- falling to cold spawn";
    }

    if (!m_backgroundLaunches.contains(appId)) {
        if (m_uiStore)
            invokeVoid(m_uiStore, "openApp", {appId, name, icon});
        emit appLaunchProgress(appId, 30);
        invokeVoid(appWindowRef, "show",
                   {appId, name, icon, type.isEmpty() ? QStringLiteral("marathon") : type,
                    QVariant(), -1});
    }
    emit          appLaunchProgress(appId, 60);

    const QString runnerPath = runnerExecutablePath();

    QVariantMap   env;
    env.insert("QT_NO_XDG_DESKTOP_PORTAL", "1");
    // The app-runner's AppRunnerLifecycleObject verifies DBus callers
    // against this PID before honouring Back() / Forward(). Without it,
    // every nav-bar back-swipe is rejected and the shell falls through
    // to closeApp() → the "back-swipe backgrounds the app" bug.
    env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));

    // Always forward DPI + user-scale through the env map — bwrap's
    // --setenv (below) handles the sandboxed case, but unsandboxed
    // launches need the values too so Constants.scaleFactor in the app
    // matches the shell.
    {
        env.insert("MARATHON_DPI", QString::number(shellDpi(), 'f', 1));

        QSettings    shellSettings(QSettings::IniFormat, QSettings::UserScope,
                                   QStringLiteral("marathon-os"), QStringLiteral("Marathon Shell"));
        const double userScale =
            shellSettings.value(QStringLiteral("ui/userScaleFactor"), 1.0).toDouble();
        env.insert("MARATHON_USER_SCALE", QString::number(userScale, 'f', 3));

        // Real screen size, forwarded so the app-runner can populate
        // Constants.screenWidth/screenHeight (ScreenMetricsCpp is not
        // registered inside the sandbox, leaving them 0 — which zeroes
        // heightScaleFactor and forces isTallScreen false in every app).
        if (const QScreen *primaryScreen = QGuiApplication::primaryScreen()) {
            const QRect g = primaryScreen->geometry();
            env.insert("MARATHON_SCREEN_WIDTH", QString::number(g.width()));
            env.insert("MARATHON_SCREEN_HEIGHT", QString::number(g.height()));
        }

        // Initial app-runner canvas, from DeviceProfile (L5 default 540x1140).
        // The runner reads these exact names; sourcing them here lets a device
        // overlay set its own canvas without touching the runner binary.
        const QSize appSize = initialAppSize();
        env.insert("MARATHON_APP_WIDTH", QString::number(appSize.width()));
        env.insert("MARATHON_APP_HEIGHT", QString::number(appSize.height()));

        // Input method for SPAWNED clients: QT_IM_MODULE=wayland.
        // QtVirtualKeyboard has no Wayland client-side IM backend (Qt 6.x
        // qtbase/src/plugins/platforms/wayland/qwaylandintegration.cpp);
        // forwarding the compositor's qtvirtualkeyboard value here makes
        // the app's QPA refuse to load any IM and emit the qWayland
        // warning. The keyboard is rendered by the compositor; apps just
        // speak text-input-v3 to it via the wayland IM client backend.
        env.insert("QT_IM_MODULE", "wayland");

        // QSG_ANTIALIASING_METHOD=vertex — same reasoning as the compositor
        // probe. Etnaviv has no FBO MSAA; vertex AA covers Shape strokes.
        env.insert("QSG_ANTIALIASING_METHOD",
                   envValue("QSG_ANTIALIASING_METHOD", QStringLiteral("vertex")));

        // MSAA samples for layered items. 0 silences "Layer requested N
        // samples but multisample renderbuffers are not supported" on
        // etnaviv. Shell's main.cpp probes the GPU and exports the chosen
        // value; we forward whatever the shell decided.
        env.insert("MARATHON_LAYER_SAMPLES", envValue("MARATHON_LAYER_SAMPLES", QStringLiteral("0")));

        if (qEnvironmentVariableIntValue("MARATHON_STARTUP_TIMING") != 0)
            env.insert("MARATHON_STARTUP_TIMING", "1");

        // QSG_RENDER_TIMING -> Qt logs per-frame scenegraph breakdown
        // (polish/sync/render + distance-field glyph-cache generation time).
        // Forwarded into the sandbox so the ~10s render-thread cold-launch
        // burn can be split between glyph generation, texture upload, and
        // effect rendering. Opt-in via the shell env; costs nothing off.
        if (qEnvironmentVariableIntValue("QSG_RENDER_TIMING") != 0)
            env.insert("QSG_RENDER_TIMING", "1");

        // Per-device driver pin (etnaviv on L5, v3d on Pi 5) — skips Mesa's
        // doomed Zink/dri2 probe chain at every app's EGL init. The WebEngine
        // branch below overwrites this with its own value.
        const QByteArray appMesaDriver = qgetenv("MARATHON_APP_MESA_DRIVER");
        if (!appMesaDriver.isEmpty())
            env.insert("MESA_LOADER_DRIVER_OVERRIDE", QString::fromLatin1(appMesaDriver));

        // Locale for VirtualKeyboard spellcheck (hunspell). Without LANG,
        // hunspell looks for dictionaries under "C" and finds nothing —
        // predictive text and autocorrect silently fail. Inherits the
        // user-chosen locale from the shell env if set, falls back to
        // en_US.UTF-8. (Hunspell-en-us dictionaries land via the image
        // depends; see pmaports.)
        env.insert("LANG", envValue("LANG", QStringLiteral("en_US.UTF-8")));

        // GPU HDR gate. AppBackdropBlur and any future MultiEffect/Shader
        // sources that want linear-precise compositing read this — defaults
        // off so etnaviv (Librem 5) skips the RGBA16F renderbuffer path
        // that QRhi can't allocate on this GPU ("Attempted to set
        // unsupported texture format 8"). Inherit from shell env or
        // default 0.
        env.insert("MARATHON_GPU_HDR", envValue("MARATHON_GPU_HDR", QStringLiteral("0")));
    }

    QStringList permissions = app.value("permissions").toStringList();
    QStringList requiresQt  = app.value("requiresQtModules").toStringList();
    QString     manifestChromiumFlags;
    // resolveAppObject populates only id/name/icon/type/exec/permissions
    // from the App model -- the model never exposed requiresQtModules, so
    // every map that reaches this path has an empty requiresQt. Until the
    // App model is extended, fall back to a manifest read for the appId.
    //
    // Same lookup also pulls the optional `chromiumFlags` string (one
    // line, space-separated --foo=bar tokens). Apps with WebGL-only
    // content (Maps via MapLibre GL JS) need flags that re-enable WebGL
    // on top of the device-wide etnaviv-safe baseline; the manifest
    // value lets an app declare exactly what shape it needs without
    // the shell having to special-case appIds.
    if (requiresQt.isEmpty() || manifestChromiumFlags.isEmpty()) {
        // Manifests are immutable at runtime; cache to keep this synchronous
        // read off the per-launch path.
        struct ManifestBits {
            QStringList requiresQt;
            QString     chromiumFlags;
        };
        static QHash<QString, ManifestBits> manifestCache;

        const QString                       appId = app.value("id").toString();
        // const_iterator throughout: insert() returns a (mutable) iterator, so
        // assigning it back to a const_iterator-initialised variable mixed the
        // two types.
        QHash<QString, ManifestBits>::const_iterator it = manifestCache.constFind(appId);
        if (it == manifestCache.constEnd()) {
            ManifestBits bits;
            QFile        mf(QStringLiteral("/usr/share/marathon-apps/%1/manifest.json").arg(appId));
            if (mf.open(QIODevice::ReadOnly)) {
                QJsonDocument     doc  = QJsonDocument::fromJson(mf.readAll());
                const QJsonObject root = doc.object();
                const auto        arr  = root.value(QStringLiteral("requiresQtModules")).toArray();
                for (const auto &v : arr)
                    bits.requiresQt << v.toString();
                bits.chromiumFlags =
                    root.value(QStringLiteral("chromiumFlags")).toString().trimmed();
            }
            it = QHash<QString, ManifestBits>::const_iterator(manifestCache.insert(appId, bits));
        }
        if (requiresQt.isEmpty())
            requiresQt = it->requiresQt;
        if (manifestChromiumFlags.isEmpty())
            manifestChromiumFlags = it->chromiumFlags;
    }
    const bool usesWebEngine = requiresQt.contains(QStringLiteral("webengine"));

    // WebEngine on etnaviv GC7000Lite: Mesa 24+ picks Zink (GL-on-Vulkan)
    // by default and etnaviv has no Vulkan ICD, so vkEnumeratePhysicalDevices
    // returns nothing and Chromium falls back to llvmpipe (or worse, dies).
    // Force the etnaviv Gallium driver, cap GLES to 2.0 (GLES3 still WIP
    // per Christian Gmeiner 2026-02), and tell Chromium to use ANGLE on
    // EGL — the only combination that initialises cleanly on this hardware.
    // Applied only to apps that declare webengine in requiresQtModules so
    // native QML apps don't pay the GLES2 cap.
    // Per-app chromium flags resolution: shell env (operator override) →
    // manifest "chromiumFlags" → device-wide default. Kept as a local so
    // both the un-sandboxed env.insert and the bwrap --setenv path below
    // emit the same value.
    const QString effectiveChromiumFlags = qEnvironmentVariable(
        "QTWEBENGINE_CHROMIUM_FLAGS",
        manifestChromiumFlags.isEmpty() ? QString::fromLatin1(deviceChromiumFlags()) :
                                          manifestChromiumFlags);

    // The runner is a Wayland CLIENT of the shell's compositor. Without
    // QT_QPA_PLATFORM=wayland Qt falls back to eglfs, which (a) fights
    // the shell's eglfs over the same DRM master and (b) hits the same
    // "OpenGL windows cannot be mixed" FATAL the moment WebEngineView
    // wants a second offscreen surface. Force every runner to use the
    // wayland QPA so it connects to the shell's compositor socket.
    // Hard-set (no qEnvironmentVariable fallback) because the shell
    // process is launched under greetd with QT_QPA_PLATFORM=eglfs in
    // its own env — if we inherited, every runner would also come up
    // on eglfs. WAYLAND_DISPLAY needs to point at the shell's
    // compositor socket name (MARATHON_WL_SOCKET_NAME, default
    // "marathon-wayland-0"), not whatever the shell's own
    // WAYLAND_DISPLAY happened to be when greetd launched it.
    env.insert("QT_QPA_PLATFORM", QStringLiteral("wayland"));
    env.insert(
        "WAYLAND_DISPLAY",
        qEnvironmentVariable("MARATHON_WL_SOCKET_NAME", QStringLiteral("marathon-wayland-0")));

    if (usesWebEngine) {
        // Qt Quick's scenegraph still needs a GL context for the runner's
        // QML chrome (URL bar, tabs, etc). QT_OPENGL=es2 + Wayland QPA
        // means Qt opens a wayland-egl context that etnaviv satisfies
        // with GLES2 directly. QT_OPENGL is a QPA HINT — the actual fix
        // that lets Mesa accept the context request is the runner's
        // QSurfaceFormat::setDefaultFormat(OpenGLES, 2.0) before
        // QGuiApplication (tools/marathon-app-runner/main.cpp:498).
        env.insert("QT_OPENGL", envValue("QT_OPENGL", QStringLiteral("es2")));
        // EGL_PLATFORM=wayland pins Mesa's _eglGetNativePlatform to the
        // wayland binding before native-display sniffing. Without it
        // Mesa's lookup order can pick up gbm/drm when both libraries
        // are linked, leading to surfaceless EGL contexts that don't
        // match the wayland-egl client surface the runner needs. Cheap
        // insurance against ambiguous Mesa platform discovery.
        env.insert("EGL_PLATFORM", QStringLiteral("wayland"));
        // Experimental etnaviv ES3-context override, OFF by default. The GC7000
        // rev 6214 is GLES3-class silicon but etnaviv still gates Mesa's GLES3
        // conformance, so Chromium's ES3 WebGL context request fails. Forcing
        // MESA_GLES_VERSION_OVERRIDE=3.0 lets ES3 context CREATION through — but
        // on Mesa 26.1.1 that does NOT produce working WebGL (Chromium SIGTRAPs
        // at MapLibre init, injection-verified) and destabilises Maps, so it
        // ships disabled. Opt in for testing by setting MARATHON_MESA_GLES_OVERRIDE
        // (e.g. =3.0); unset means we leave Mesa's default ES2 advertisement alone.
        const QByteArray glesOverride = qgetenv("MARATHON_MESA_GLES_OVERRIDE");
        if (!glesOverride.isEmpty())
            env.insert("MESA_GLES_VERSION_OVERRIDE", QString::fromLatin1(glesOverride));
        env.insert("QTWEBENGINE_CHROMIUM_FLAGS", effectiveChromiumFlags);
        // Do NOT force MESA_LOADER_DRIVER_OVERRIDE / GALLIUM_DRIVER /
        // GBM_BACKEND to "etnaviv". On this render node the Mesa loader
        // front-end is kmsro (etnaviv is render-only behind it); pinning
        // the loader straight to etnaviv makes eglInitialize fail to
        // create the DRI2 screen -> EGL_NOT_INITIALIZED -> QRhiGles2
        // "Failed to create context" -> SceneGraphError -> the runner
        // aborts (SIGABRT). This is the same failure the native-app path
        // below documents and avoids by leaving the override UNSET. The
        // bwrap cage binds only renderD128 (see --dev-bind-try below), so
        // Mesa auto-selects kmsro->etnaviv on its own, and wl_drm names
        // the device explicitly — exactly what the native apps do. The
        // greetd-inherited kmsro override is cleared per-app by the
        // `--unsetenv MESA_LOADER_DRIVER_OVERRIDE` in the bwrap args.
        // Tell wayland-egl clients which DRM render node to allocate on,
        // in lieu of Qt Wayland Compositor advertising linux-dmabuf-v1 v4
        // feedback (Qt 6.11 docs still title the attribution page
        // "unstable v3"; the v4 main_device feedback event is what phoc
        // ships and what Mesa clients use to discover renderD128). Phosh
        // distributes this same env var as their workaround for
        // wlroots#3757.
        env.insert("WLR_RENDER_DRM_DEVICE",
                   qEnvironmentVariable("WLR_RENDER_DRM_DEVICE",
                                        DeviceProfile::instance().renderNode()));
    }

    if (permissions.contains("network")) {
        env.insert("MARATHON_PERM_NETWORK", "1");
    }
    if (permissions.contains("storage")) {
        env.insert("MARATHON_PERM_STORAGE", "1");
    }
    // Secret Service (org.freedesktop.secrets) lives on the session bus.
    // The session bus socket is already inside the sandbox via the
    // XDG_RUNTIME_DIR bind (it shares the same dir as the Wayland socket
    // we MUST expose), so no extra bwrap flag is needed. Instead we
    // surface the permission as an env var the app/helper can gate on —
    // marathon-mail-oauth refuses to read/write keyring entries unless
    // MARATHON_PERM_SECRET_SERVICE=1 is set in its environment.
    if (permissions.contains("secret-service")) {
        env.insert("MARATHON_PERM_SECRET_SERVICE", "1");
    }

    const bool userInstalled = isUserInstalled(appId);

    // Warm pool: hand a pre-initialised runner this app instead of paying
    // exec + dynamic linking + Qt init on the critical path (~1s of the
    // ~2s tap-to-frame measured 2026-07-02). WebEngine apps keep the cold
    // path — their env is per-app. The spare can write every app's data
    // directory, so it only takes Marathon's own apps.
    if (!userInstalled && !usesWebEngine) {
        const SpareShape shape = permissions.contains("storage") ? StorageSpare : PlainSpare;
        noteLaunchShape(shape);
        PendingLaunch pooled;
        pooled.appId   = appId;
        pooled.name    = name;
        pooled.icon    = icon;
        pooled.type    = type.isEmpty() ? QStringLiteral("marathon") : type;
        pooled.command = QStringLiteral("pool-adopt ") + appId;
        if (adoptSpareRunner(shape, pooled, env)) {
            QTimer::singleShot(10000, this, [this, appId]() { m_launchingApps.remove(appId); });
            emit appLaunchProgress(appId, 100);
            emit appLaunchCompleted(appId, name);
            return true;
        }
    }

    // Build the app command. If bubblewrap is present, wrap marathon-app-runner
    // in a sandbox so an app process can no longer reach the shell's QSettings
    // store, notifications.db, app-permissions.json, etc. through plain
    // filesystem ops. Without bwrap, the app-runner runs unsandboxed (same UID
    // as the shell) -- callers should still rely on the D-Bus permission gate
    // for everything sensitive, but bwrap closes the obvious bypass.
    //
    // Policy summary (per app):
    //   - read-only bind  : /usr, /etc, /lib, /lib64 (binaries + Qt + system config)
    //   - read-only bind  : ~/.config/marathon-apps/<appId> (per-app config seed)
    //   - read-only bind  : XDG_DATA_HOME/marathon/apps/<appId> (a user install)
    //   - read-write bind : XDG_DATA_HOME/marathon-apps/<appId>            (data)
    //   - read-write bind : XDG_CACHE_HOME/marathon-apps/<appId>           (cache)
    //   - pass through    : XDG_RUNTIME_DIR (Wayland + user D-Bus sockets)
    //   - read-write bind : XDG user dirs + ~/DCIM, only with "storage"
    //   - tmpfs           : everything else under /home, /tmp
    //   - no network namespace unless "network" permission granted
    //   - --die-with-parent so a hung sandbox can't outlive the shell
    const QString bwrapPath = QStandardPaths::findExecutable("bwrap");
    QString       cmd;
    QString       sandboxInstance;
    if (!bwrapPath.isEmpty() && !qEnvironmentVariableIsSet("MARATHON_DISABLE_SANDBOX")) {
        sandboxInstance             = newSandboxInstance();
        const QString waylandSocket = openSandboxSocket(appId, sandboxInstance);
        if (waylandSocket.isEmpty()) {
            qWarning() << "[AppLaunchService] No sandbox Wayland socket for" << appId
                       << "- not launching";
            m_launchingApps.remove(appId);
            emit appLaunchFailed(appId, name, "No sandbox Wayland socket");
            return false;
        }
        const QString xdgRuntimeDir = envValue("XDG_RUNTIME_DIR", QStringLiteral("/run/user/1000"));
        const QString homeDir       = envValue("HOME", QStringLiteral("/home/user"));
        const QString xdgDataHome =
            qEnvironmentVariable("XDG_DATA_HOME", QStringLiteral("%1/.local/share").arg(homeDir));
        const QString xdgCacheHome =
            qEnvironmentVariable("XDG_CACHE_HOME", QStringLiteral("%1/.cache").arg(homeDir));
        const QString xdgConfigHome =
            qEnvironmentVariable("XDG_CONFIG_HOME", QStringLiteral("%1/.config").arg(homeDir));

        const QString appData   = QStringLiteral("%1/marathon-apps/%2").arg(xdgDataHome, appId);
        const QString appCache  = QStringLiteral("%1/marathon-apps/%2").arg(xdgCacheHome, appId);
        const QString appConfig = QStringLiteral("%1/marathon-apps/%2").arg(xdgConfigHome, appId);
        QDir().mkpath(appData);
        QDir().mkpath(appCache);
        QDir().mkpath(appConfig);

        QStringList bwrapArgs;
        // The DRM render node the sandbox exposes and the client renders on.
        // DeviceProfile resolves MARATHON_RENDER_NODE > conf RENDER_NODE >
        // /dev/dri/renderD128, so an overlay can retarget it and the bwrap
        // bind, the WLR device hint, and the client all stay in agreement.
        const QString renderNode = DeviceProfile::instance().renderNode();
        bwrapArgs << QStringLiteral("--die-with-parent") << QStringLiteral("--new-session");
        // The shell's eglfs driver pin (kmsro on the L5) must never reach
        // clients: on the render node it sends Mesa to software rendering.
        // MARATHON_APP_MESA_DRIVER re-pins below when set; otherwise Mesa
        // auto-detects the right driver for the render node.
        bwrapArgs << QStringLiteral("--unsetenv") << QStringLiteral("MESA_LOADER_DRIVER_OVERRIDE")
                  << QStringLiteral("--unsetenv") << QStringLiteral("ETNA_MESA_DEBUG");
        // NB: native (non-WebEngine) apps must launch with the Mesa loader
        // driver UNSET. On etnaviv the loader front-end is kmsro (etnaviv is
        // render-only behind it); pinning MESA_LOADER_DRIVER_OVERRIDE=etnaviv
        // makes QRhiGles2 fail to create a context -> no surface -> launch
        // timeout. Mesa auto-selects kmsro->etnaviv correctly on its own.

        // WebEngine apps too: Chromium's namespace sandbox nests inside these.
        bwrapArgs << QStringLiteral("--unshare-pid") << QStringLiteral("--unshare-uts")
                  << QStringLiteral("--unshare-ipc") << QStringLiteral("--unshare-cgroup-try")
                  << QStringLiteral("--unshare-user-try");
        if (!permissions.contains("network"))
            bwrapArgs << QStringLiteral("--unshare-net");

        bwrapArgs << QStringLiteral("--ro-bind") << QStringLiteral("/usr") << QStringLiteral("/usr")
                  << QStringLiteral("--ro-bind") << QStringLiteral("/etc") << QStringLiteral("/etc")
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/lib")
                  << QStringLiteral("/lib") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/lib64") << QStringLiteral("/lib64")
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/bin")
                  << QStringLiteral("/bin") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/sbin") << QStringLiteral("/sbin")
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/var/empty")
                  << QStringLiteral("/var/empty") << QStringLiteral("--proc")
                  << QStringLiteral("/proc") << QStringLiteral("--dev")
                  << QStringLiteral("/dev")
                  // Bind ONLY the render node (renderD128), not the whole
                  // /dev/dri/ tree. The shell holds DRM master on card1
                  // (mxsfb DSI scanout); exposing card1 to the runner means
                  // Chromium probes it, fails the master-only mode-set
                  // ioctls (EACCES), then falls back to renderD128 and
                  // tries MODE_CREATE_DUMB — which render nodes don't
                  // support, producing the cascading "Failed to create GBM
                  // buffer" we saw on the L5. Restricting to renderD128
                  // forces Mesa straight to the render-only GBM path:
                  // gbm_bo_create(... GBM_BO_USE_RENDERING), dmabuf export,
                  // wl_buffer import — exactly what phoc/Phosh clients do
                  // and what Igalia's WPEBackend-fdo does in production.
                  << QStringLiteral("--dev-bind-try") << renderNode << renderNode
                  // /sys is needed for GPU/DRM driver discovery: Mesa walks
                  // /sys/dev/char/<major:minor> → /sys/class/drm/renderD128
                  // → /sys/devices/.../pci... to pick the right DRI driver.
                  // Bind the whole tree first, then explicitly the
                  // dev/char, class/drm and devices subtrees the symlink
                  // walk needs to traverse — bwrap's --ro-bind /sys
                  // alone has been observed to miss symlink-target
                  // namespaces and cause eglCreateContext: dri2_create_context
                  // (Flatpak#5543 / steam-runtime#683 — same symptom on
                  // sandboxed Wayland GL clients). The bind-try entries
                  // are no-ops where the directory doesn't exist on
                  // particular kernels.
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys")
                  << QStringLiteral("/sys") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/sys/dev/char") << QStringLiteral("/sys/dev/char")
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys/class/drm")
                  << QStringLiteral("/sys/class/drm") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/sys/devices")
                  << QStringLiteral("/sys/devices")
                  // System D-Bus socket lives at /run/dbus/system_bus_socket
                  // (Alpine path; older distros at /var/run/dbus). Apps
                  // need it to reach ModemManager / NetworkManager / UPower
                  // / Bluez. Without this the runner logs
                  // "Failed to connect to socket /run/dbus/system_bus_socket".
                  // /etc/resolv.conf is a SYMLINK into /run/systemd/resolve
                  // on this image. /etc is bound read-only above, so the
                  // symlink itself is present inside the sandbox -- but its
                  // target was not, leaving it dangling. Every sandboxed app
                  // therefore failed DNS: Qt reported "Host <name> not found"
                  // and QML XHR surfaced that as status 0, which is what made
                  // the Store's Discover tab unreachable even though the app
                  // holds the "network" permission and the sandbox shares the
                  // host network namespace. Bind the resolver state too.
                  << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/run/systemd/resolve")
                  << QStringLiteral("/run/systemd/resolve")
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/run/dbus")
                  << QStringLiteral("/run/dbus") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/var/run/dbus") << QStringLiteral("/var/run/dbus")
                  << QStringLiteral("--tmpfs")
                  << QStringLiteral("/tmp")
                  // Chromium uses POSIX shared memory at /dev/shm for its
                  // inter-process buffers. The --dev /dev mount above gives
                  // us a fresh tmpfs at /dev but it doesn't include
                  // /dev/shm, and Chromium SIGTRAPs in shared-memory init
                  // when the path is missing or read-only. Mount a tmpfs
                  // so chromium can create files there.
                  << QStringLiteral("--tmpfs") << QStringLiteral("/dev/shm")
                  << QStringLiteral("--tmpfs") << homeDir << QStringLiteral("--ro-bind")
                  << QStringLiteral("/usr/share/marathon-apps")
                  << QStringLiteral("/usr/share/marathon-apps") << QStringLiteral("--ro-bind-try")
                  << appConfig << appConfig << QStringLiteral("--bind") << appData << appData
                  << QStringLiteral("--bind") << appCache << appCache << QStringLiteral("--bind")
                  << xdgRuntimeDir << xdgRuntimeDir << QStringLiteral("--ro-bind-try")
                  << xdgConfigHome + QStringLiteral("/dconf")
                  << xdgConfigHome + QStringLiteral("/dconf");
        bwrapArgs << waylandSocketArgs(waylandSocket, xdgRuntimeDir);

        bwrapArgs << installBinds(appId, permissions);

        if (permissions.contains("storage"))
            bwrapArgs << storageBinds(homeDir);

        // Pass HOME as a tmpfs-mounted directory; apps can write to their
        // per-app data/cache paths only.
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("HOME") << homeDir
                  << QStringLiteral("--setenv") << QStringLiteral("XDG_DATA_HOME") << xdgDataHome
                  // The app's own cache, like Flatpak's; the rest of ~/.cache is tmpfs.
                  << QStringLiteral("--setenv") << QStringLiteral("XDG_CACHE_HOME") << appCache
                  << QStringLiteral("--setenv") << QStringLiteral("QML_DISK_CACHE_PATH")
                  << appCache + QStringLiteral("/qmlcache")
                  << QStringLiteral("--setenv") << QStringLiteral("XDG_CONFIG_HOME")
                  << xdgConfigHome
                  // app-runner verifies DBus callers against this PID on Back/Forward.
                  << QStringLiteral("--setenv") << QStringLiteral("MARATHON_SHELL_PID")
                  << QString::number(QCoreApplication::applicationPid());

        // Propagate the shell's user scale factor and detected DPI into the
        // sandbox. Apps don't get SettingsManagerCpp or ScreenMetricsCpp
        // (those are shell-only singletons), so without this they always
        // render at scaleFactor = 1.0 while shell chrome scales by DPI. The
        // resulting size mismatch is visible as tiny status bar / huge app
        // (or vice-versa) the moment the user picks a non-default scale.
        {
            QSettings    shellSettings(QSettings::IniFormat, QSettings::UserScope,
                                       QStringLiteral("marathon-os"),
                                       QStringLiteral("Marathon Shell"));
            const double userScale =
                shellSettings.value(QStringLiteral("ui/userScaleFactor"), 1.0).toDouble();
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_USER_SCALE")
                      << QString::number(userScale, 'f', 3);
        }
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_DPI")
                  << QString::number(shellDpi(), 'f', 1);
        if (const QScreen *primaryScreen = QGuiApplication::primaryScreen()) {
            const QRect g = primaryScreen->geometry();
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_SCREEN_WIDTH")
                      << QString::number(g.width()) << QStringLiteral("--setenv")
                      << QStringLiteral("MARATHON_SCREEN_HEIGHT") << QString::number(g.height());
        }

        // QT_QPA_PLATFORM=wayland makes the sandboxed runner connect to
        // the shell's compositor socket as a Wayland client. Hard-set
        // (no fallback) because the shell itself runs under
        // QT_QPA_PLATFORM=eglfs from greetd's env — inheriting that
        // would land every runner back on eglfs and re-trigger the
        // "OpenGL windows cannot be mixed" FATAL.
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QT_QPA_PLATFORM")
                  << QStringLiteral("wayland");
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("WAYLAND_DISPLAY")
                  << qEnvironmentVariable("MARATHON_WL_SOCKET_NAME",
                                          QStringLiteral("marathon-wayland-0"));
        // QT_IM_MODULE=wayland for clients — not qtvirtualkeyboard (see
        // unsandboxed path above for the reasoning). Layer MSAA suppression
        // + GPU HDR + vertex-AA propagation as before.
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QT_IM_MODULE")
                  << QStringLiteral("wayland");
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QSG_ANTIALIASING_METHOD")
                  << envValue("QSG_ANTIALIASING_METHOD", QStringLiteral("vertex"));
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_LAYER_SAMPLES")
                  << envValue("MARATHON_LAYER_SAMPLES", QStringLiteral("0"));
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_GPU_HDR")
                  << envValue("MARATHON_GPU_HDR", QStringLiteral("0"));
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("LANG")
                  << envValue("LANG", QStringLiteral("en_US.UTF-8"));

        // WebEngine GPU shape — see kDefaultChromiumFlags + the
        // un-sandboxed env block above for the full reasoning. QT_OPENGL
        // pins Qt's GL context request to GLES2 (etnaviv's only profile)
        // so QRhi comes up cleanly; ANGLE→native libGL handles the same
        // underneath for chromium.
        if (usesWebEngine) {
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QT_OPENGL")
                      << envValue("QT_OPENGL", QStringLiteral("es2"));
            // Deliberately do NOT --setenv MESA_LOADER_DRIVER_OVERRIDE /
            // GBM_BACKEND / GALLIUM_DRIVER to etnaviv here. Forcing the
            // loader to etnaviv makes eglInitialize fail the DRI2 screen
            // (EGL_NOT_INITIALIZED) and QRhiGles2 abort — see the
            // un-sandboxed block above and the native-app note by the
            // `--unsetenv MESA_LOADER_DRIVER_OVERRIDE` arg. The cage binds
            // only renderD128, so Mesa auto-selects kmsro->etnaviv and
            // wl_drm names the device; WebEngine apps now come up on the
            // same working path as native QML apps.
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("WLR_RENDER_DRM_DEVICE")
                      << qEnvironmentVariable("WLR_RENDER_DRM_DEVICE", renderNode);
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("EGL_PLATFORM")
                      << QStringLiteral("wayland");
            // Experimental etnaviv ES3 override — OFF by default, same as the
            // un-sandboxed block. Forcing MESA_GLES_VERSION_OVERRIDE=3.0 does
            // NOT yield working WebGL on Mesa 26.1.1 (Chromium SIGTRAPs at
            // MapLibre init) and destabilises Maps, so we only pass it through
            // when MARATHON_MESA_GLES_OVERRIDE is explicitly set for testing.
            const QByteArray glesOverride = qgetenv("MARATHON_MESA_GLES_OVERRIDE");
            if (!glesOverride.isEmpty())
                bwrapArgs << QStringLiteral("--setenv")
                          << QStringLiteral("MESA_GLES_VERSION_OVERRIDE")
                          << QString::fromLatin1(glesOverride);
            // The chromium flags value contains spaces (multiple --foo=bar
            // tokens) and the cmd string we build here is re-parsed by
            // QProcess::splitCommand on the compositor side. Per Qt 6 docs
            // QProcess::splitCommand only recognises DOUBLE quotes — single
            // quotes pass through literally. Without quoting, splitCommand
            // chops the value into separate args and bwrap sees
            // `--disable-gpu` as its own flag — "bwrap: Unknown option
            // --disable-gpu" and the WebEngine app fails to launch. The
            // chromium flags value doesn't contain any double quotes itself
            // so wrapping is safe. Quoting is now done once, generically,
            // by quoteForSplitCommand() at the join below.
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QTWEBENGINE_CHROMIUM_FLAGS")
                      << effectiveChromiumFlags;
        }

        cmd = bwrapPath + QStringLiteral(" ") + joinForSplitCommand(bwrapArgs)
            + QStringLiteral(" ") + runnerPath + QStringLiteral(" --app-id ") + appId;
        env.insert("MARATHON_SANDBOXED", "1");
        qInfo() << "[AppLaunchService] Launching" << appId << "in bubblewrap sandbox (network="
                << (permissions.contains("network") ? "yes" : "no") << ")";
    } else {
        cmd = QStringLiteral("%1 --app-id %2").arg(runnerPath, appId);
        qWarning() << "[AppLaunchService] Launching" << appId
                   << "WITHOUT sandbox (bwrap missing or MARATHON_DISABLE_SANDBOX set)";
    }

    if (!m_pendingRoute.isEmpty()) {
        // Quote the route so paths with spaces survive Wayland-side parsing
        // (the runner uses QCommandLineParser which handles quoted args).
        cmd += QStringLiteral(" --route \"%1\"").arg(m_pendingRoute);
        env.insert("MARATHON_APP_ROUTE", m_pendingRoute);
        if (!m_pendingRouteParamsJson.isEmpty())
            env.insert("MARATHON_APP_ROUTE_PARAMS", m_pendingRouteParamsJson);
    }
    m_pendingRoute.clear();
    m_pendingRouteParamsJson.clear();

    PendingLaunch p;
    p.appId   = appId;
    p.name    = name;
    p.icon    = icon;
    p.type            = type.isEmpty() ? QStringLiteral("marathon") : type;
    p.command         = cmd;
    p.sandboxInstance = sandboxInstance;
    m_pendingByCommand.insert(cmd, p);

    const bool ok = QMetaObject::invokeMethod(comp, "launchApp", Qt::DirectConnection,
                                              Q_ARG(QString, cmd), Q_ARG(QVariantMap, env));
    if (!ok)
        qWarning() << "[AppLaunchService] Failed to invoke launchApp(QString, QVariantMap) on "
                      "compositor";

    // Hold m_launchingApps until either the surface attaches (TaskModel
    // reports the new task) or 10 s elapses — whichever comes first. Without
    // the hold, a second tap that arrives during the WebEngine cold-start
    // window (60-90s) passes the dedupe check and spawns a parallel runner.
    QTimer::singleShot(10000, this, [this, appId]() { m_launchingApps.remove(appId); });

    emit appLaunchProgress(appId, 100);
    emit appLaunchCompleted(appId, name);
    return true;
}

QString AppLaunchService::openSandboxSocket(const QString &appId, const QString &instanceId) const {
    QString socket;
    if (m_compositor)
        QMetaObject::invokeMethod(m_compositor.data(), "openSandboxSocket", Qt::DirectConnection,
                                  Q_RETURN_ARG(QString, socket), Q_ARG(QString, appId),
                                  Q_ARG(QString, instanceId));
    return socket;
}

void AppLaunchService::closeSandboxSocket(const QString &instanceId) const {
    if (m_compositor && !instanceId.isEmpty())
        QMetaObject::invokeMethod(m_compositor.data(), "closeSandboxSocket", Qt::DirectConnection,
                                  Q_ARG(QString, instanceId));
}

bool AppLaunchService::isUserInstalled(const QString &appId) {
    return !QFile::exists(MarathonAppPaths::systemApps() + "/" + appId + "/manifest.json") &&
        QFile::exists(MarathonAppPaths::receiptPath(appId));
}

QStringList AppLaunchService::installBinds(const QString &appId, const QStringList &permissions) {
    if (isUserInstalled(appId)) {
        const QString install = MarathonAppPaths::installDir(appId);
        return {QStringLiteral("--ro-bind"), install, install};
    }
    if (permissions.contains(QStringLiteral("system"))) {
        const QString installs = MarathonAppPaths::userInstalls();
        return {QStringLiteral("--ro-bind-try"), installs, installs};
    }
    return {};
}

QString AppLaunchService::runnerExecutablePath() const {
    const QDir shellBinDir(QCoreApplication::applicationDirPath());
    QString    candidate = shellBinDir.filePath("../tools/marathon-app-runner/marathon-app-runner");
    if (QFileInfo::exists(candidate))
        return candidate;
    return QStringLiteral("marathon-app-runner");
}

// Neutral sandbox for the spare: same shape as the per-app recipe in
// launchMarathonApp minus everything app-specific. The per-app data dirs
// are replaced by their parents (the app id is unknown at spawn) and the
// network namespace is shared — both a deliberate loosening, scoped to
// pool-adopted first-party apps. WebEngine apps never adopt. Only a
// StorageSpare sees the media folders.
QStringList AppLaunchService::spareSandboxArgs(const QString &waylandSocket,
                                               SpareShape     shape) const {
    const QString xdgRuntimeDir = envValue("XDG_RUNTIME_DIR", QStringLiteral("/run/user/1000"));
    const QString homeDir       = envValue("HOME", QStringLiteral("/home/user"));
    const QString xdgDataHome =
        qEnvironmentVariable("XDG_DATA_HOME", QStringLiteral("%1/.local/share").arg(homeDir));
    const QString xdgCacheHome =
        qEnvironmentVariable("XDG_CACHE_HOME", QStringLiteral("%1/.cache").arg(homeDir));
    const QString xdgConfigHome =
        qEnvironmentVariable("XDG_CONFIG_HOME", QStringLiteral("%1/.config").arg(homeDir));
    const QString dataDir   = xdgDataHome + QStringLiteral("/marathon-apps");
    const QString cacheDir  = xdgCacheHome + QStringLiteral("/marathon-apps");
    const QString configDir = xdgConfigHome + QStringLiteral("/marathon-apps");
    const QString renderNode = DeviceProfile::instance().renderNode();
    QDir().mkpath(cacheDir + QStringLiteral("/.spare"));

    QStringList   args;
    args << QStringLiteral("--unsetenv") << QStringLiteral("MESA_LOADER_DRIVER_OVERRIDE")
         << QStringLiteral("--unsetenv") << QStringLiteral("ETNA_MESA_DEBUG");
    args << QStringLiteral("--die-with-parent") << QStringLiteral("--new-session")
         << QStringLiteral("--unshare-pid") << QStringLiteral("--unshare-uts")
         << QStringLiteral("--unshare-ipc") << QStringLiteral("--unshare-cgroup-try")
         << QStringLiteral("--unshare-user-try");

    args << QStringLiteral("--ro-bind") << QStringLiteral("/usr") << QStringLiteral("/usr")
         << QStringLiteral("--ro-bind") << QStringLiteral("/etc") << QStringLiteral("/etc")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/lib") << QStringLiteral("/lib")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/lib64") << QStringLiteral("/lib64")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/bin") << QStringLiteral("/bin")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sbin") << QStringLiteral("/sbin")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/var/empty")
         << QStringLiteral("/var/empty") << QStringLiteral("--proc") << QStringLiteral("/proc")
         << QStringLiteral("--dev") << QStringLiteral("/dev") << QStringLiteral("--dev-bind-try")
         << renderNode << renderNode
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys") << QStringLiteral("/sys")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys/dev/char")
         << QStringLiteral("/sys/dev/char") << QStringLiteral("--ro-bind-try")
         << QStringLiteral("/sys/class/drm") << QStringLiteral("/sys/class/drm")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys/devices")
         << QStringLiteral("/sys/devices") << QStringLiteral("--ro-bind-try")
         << QStringLiteral("/run/dbus") << QStringLiteral("/run/dbus")
         // See the note on the other bwrap builder: /etc/resolv.conf is a
         // symlink into /run/systemd/resolve, so binding /etc alone leaves
         // DNS broken inside the sandbox.
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/run/systemd/resolve")
         << QStringLiteral("/run/systemd/resolve")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/var/run/dbus")
         << QStringLiteral("/var/run/dbus") << QStringLiteral("--tmpfs") << QStringLiteral("/tmp")
         << QStringLiteral("--tmpfs") << QStringLiteral("/dev/shm") << QStringLiteral("--tmpfs")
         << homeDir << QStringLiteral("--ro-bind") << QStringLiteral("/usr/share/marathon-apps")
         << QStringLiteral("/usr/share/marathon-apps") << QStringLiteral("--ro-bind-try")
         << configDir << configDir << QStringLiteral("--bind") << dataDir << dataDir
         << QStringLiteral("--bind") << cacheDir << cacheDir << QStringLiteral("--bind")
         << xdgRuntimeDir << xdgRuntimeDir << QStringLiteral("--ro-bind-try")
         << MarathonAppPaths::userInstalls() << MarathonAppPaths::userInstalls()
         // Nemo.Configuration reads dconf's database file; writes go to the
         // dconf service over D-Bus.
         << QStringLiteral("--ro-bind-try") << xdgConfigHome + QStringLiteral("/dconf")
         << xdgConfigHome + QStringLiteral("/dconf");
    args << waylandSocketArgs(waylandSocket, xdgRuntimeDir);
    if (shape == StorageSpare)
        args << storageBinds(homeDir);

    args << QStringLiteral("--setenv") << QStringLiteral("HOME") << homeDir
         << QStringLiteral("--setenv") << QStringLiteral("XDG_DATA_HOME") << xdgDataHome
         // Spares only ever become Marathon's own apps, so they share one cache.
         << QStringLiteral("--setenv") << QStringLiteral("XDG_CACHE_HOME")
         << cacheDir + QStringLiteral("/.spare") << QStringLiteral("--setenv")
         << QStringLiteral("QML_DISK_CACHE_PATH") << cacheDir + QStringLiteral("/.spare/qmlcache")
         << QStringLiteral("--setenv") << QStringLiteral("XDG_CONFIG_HOME") << xdgConfigHome
         << QStringLiteral("--setenv") << QStringLiteral("MARATHON_SHELL_PID")
         << QString::number(QCoreApplication::applicationPid()) << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_SANDBOXED") << QStringLiteral("1")
         // Initial canvas from DeviceProfile, same as the on-demand launch path
         // — so a preforked pool spare boots at the device's own size instead of
         // the runner's built-in 540x1140 fallback (matters on non-L5 devices).
         << QStringLiteral("--setenv") << QStringLiteral("MARATHON_APP_WIDTH")
         << QString::number(initialAppSize().width()) << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_APP_HEIGHT") << QString::number(initialAppSize().height());

    args << QStringLiteral("--setenv") << QStringLiteral("MARATHON_DPI")
         << QString::number(shellDpi(), 'f', 1);
    if (const QScreen *primaryScreen = QGuiApplication::primaryScreen()) {
        const QRect g = primaryScreen->geometry();
        args << QStringLiteral("--setenv") << QStringLiteral("MARATHON_SCREEN_WIDTH")
             << QString::number(g.width()) << QStringLiteral("--setenv")
             << QStringLiteral("MARATHON_SCREEN_HEIGHT") << QString::number(g.height());
    }

    args << QStringLiteral("--setenv") << QStringLiteral("QT_QPA_PLATFORM")
         << QStringLiteral("wayland") << QStringLiteral("--setenv")
         << QStringLiteral("WAYLAND_DISPLAY")
         << qEnvironmentVariable("MARATHON_WL_SOCKET_NAME", QStringLiteral("marathon-wayland-0"))
         << QStringLiteral("--setenv") << QStringLiteral("QT_IM_MODULE")
         << QStringLiteral("wayland") << QStringLiteral("--setenv")
         << QStringLiteral("QSG_ANTIALIASING_METHOD")
         << envValue("QSG_ANTIALIASING_METHOD", QStringLiteral("vertex")) << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_LAYER_SAMPLES")
         << envValue("MARATHON_LAYER_SAMPLES", QStringLiteral("0")) << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_GPU_HDR") << envValue("MARATHON_GPU_HDR", QStringLiteral("0"))
         << QStringLiteral("--setenv") << QStringLiteral("LANG")
         << envValue("LANG", QStringLiteral("en_US.UTF-8"));

    const QByteArray appMesaDriver = qgetenv("MARATHON_APP_MESA_DRIVER");
    if (!appMesaDriver.isEmpty())
        args << QStringLiteral("--setenv") << QStringLiteral("MESA_LOADER_DRIVER_OVERRIDE")
             << QString::fromLatin1(appMesaDriver);
    if (qEnvironmentVariableIntValue("MARATHON_STARTUP_TIMING") != 0)
        args << QStringLiteral("--setenv") << QStringLiteral("MARATHON_STARTUP_TIMING")
             << QStringLiteral("1");
    // See the env-map forward above: QSG_RENDER_TIMING lets us split the
    // ~10s render-thread cold-launch burn (glyph gen vs texture vs render).
    if (qEnvironmentVariableIntValue("QSG_RENDER_TIMING") != 0)
        args << QStringLiteral("--setenv") << QStringLiteral("QSG_RENDER_TIMING")
             << QStringLiteral("1");

    return args;
}

// A spare that survives this long has finished Qt init and is genuinely warm;
// anything shorter means the spawn itself is broken.
static constexpr qint64 kSpareHealthyMs = 30000;
// Delay before replacing an adopted spare (see adoptSpareRunner).
static constexpr int kSpareRefillDelayMs = 8000;
// Launches a lone spare's shape is chosen from.
static constexpr qsizetype kRecentShapes = 5;

// With two spares, one of each shape. With one, the shape most of the last
// few launches needed, ties going to the latest; before any launch, storage,
// which most of Marathon's apps have.
QList<AppLaunchService::SpareShape> AppLaunchService::wantedSpareShapes() const {
    if (m_spareCount <= 0)
        return {};
    if (m_spareCount >= 2)
        return {StorageSpare, PlainSpare};
    if (m_recentShapes.isEmpty())
        return {StorageSpare};
    const qsizetype storage = m_recentShapes.count(StorageSpare);
    const qsizetype plain   = m_recentShapes.size() - storage;
    if (storage == plain)
        return {m_recentShapes.last()};
    return {storage > plain ? StorageSpare : PlainSpare};
}

void AppLaunchService::noteLaunchShape(SpareShape shape) {
    m_recentShapes.append(shape);
    if (m_recentShapes.size() > kRecentShapes)
        m_recentShapes.removeFirst();
    // A spare of a shape no longer wanted leaves; its exit schedules the
    // refill. EOF on stdin is the runner's drain request.
    const QList<SpareShape> wanted = wantedSpareShapes();
    for (int s = 0; s < SpareShapes; ++s) {
        Spare &spare = m_spares[s];
        if (!spare.process || wanted.contains(SpareShape(s)))
            continue;
        qInfo() << "[AppLaunchService] Retiring spare runner pid" << spare.pid;
        spare.process->setProperty("marathonRetired", true);
        spare.process->closeWriteChannel();
        spare = {};
    }
}

void AppLaunchService::refillSpares() {
    // A coarse timer can fire up to 5% early; wait out the rest.
    const qint64 waitMs = m_spareRetryAfterMs - QDateTime::currentMSecsSinceEpoch();
    if (waitMs > 0) {
        QTimer::singleShot(waitMs, this, &AppLaunchService::refillSpares);
        return;
    }
    const QList<SpareShape> wanted = wantedSpareShapes();
    for (qsizetype i = 0; i < wanted.size(); ++i) {
        if (m_spares[wanted[i]].process)
            continue;
        // One at a time: a spare spends seconds of CPU warming up.
        if (spawnSpareRunner(wanted[i]) && i + 1 < wanted.size())
            QTimer::singleShot(kSpareRefillDelayMs, this, &AppLaunchService::refillSpares);
        return;
    }
}

bool AppLaunchService::spawnSpareRunner(SpareShape shape) {
    // The v1 pool (measured 2026-07-02) LOST to cold launch because the idle
    // spare's warmed pages were evicted to zram and adoption faulted them
    // back. Fixed by mlockall residency in the runner (--pool): validated
    // 2026-07-06 on L5 etnaviv, pooled adopt->first-frame ~0.9-1.1s vs
    // 11-13s fresh-boot cold. RUNNER_POOL=0 in the device profile (or
    // MARATHON_RUNNER_POOL=0) gives a device the memory back.
    if (m_spares[shape].process)
        return false;
    if (m_spareFailures >= 3) {
        qWarning() << "[AppLaunchService] Runner pool disabled after repeated spare failures";
        return false;
    }
    const QString bwrapPath = QStandardPaths::findExecutable("bwrap");
    if (bwrapPath.isEmpty() || qEnvironmentVariableIsSet("MARATHON_DISABLE_SANDBOX"))
        return false; // pool covers the sandboxed production path only

    const QString homeDir = envValue("HOME", QStringLiteral("/home/user"));
    QDir().mkpath(
        qEnvironmentVariable("XDG_DATA_HOME", QStringLiteral("%1/.local/share").arg(homeDir)) +
        QStringLiteral("/marathon-apps"));
    QDir().mkpath(qEnvironmentVariable("XDG_CACHE_HOME", QStringLiteral("%1/.cache").arg(homeDir)) +
                  QStringLiteral("/marathon-apps"));

    // The spare's app is unknown until adoption; assignSandboxApp names it.
    const QString instance      = newSandboxInstance();
    const QString waylandSocket = openSandboxSocket(QString(), instance);
    if (waylandSocket.isEmpty())
        return false;

    auto *proc = new QProcess(this);
    proc->setProperty("marathonSandboxInstance", instance);
    proc->setProcessChannelMode(QProcess::SeparateChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // Shell-only startup shortcuts; see WaylandCompositor::launchApp.
    env.remove(QStringLiteral("QT_NO_BUILTIN_SELECTORS"));
    env.remove(QStringLiteral("GST_REGISTRY_UPDATE"));
    proc->setProcessEnvironment(env);
    connect(proc, &QProcess::readyReadStandardError, this, [proc]() {
        const QString     tag   = proc->property("marathonAppId").toString();
        const QStringList lines = QString::fromLocal8Bit(proc->readAllStandardError()).split('\n');
        for (const QString &l : lines) {
            const QString line = l.trimmed();
            if (!line.isEmpty())
                qInfo().noquote() << "[PoolRunner stderr]"
                                  << (tag.isEmpty() ? QStringLiteral("spare") : tag) << "->"
                                  << line;
        }
    });
    connect(proc, &QProcess::started, this, [this, proc, shape]() {
        const qint64 pid = proc->processId();
        proc->setProperty("marathonPoolPid", pid);
        Spare &spare = m_spares[shape];
        if (proc == spare.process) {
            spare.pid       = pid;
            spare.adoptable = true;
            proc->setProperty("marathonSpareStartMs", QDateTime::currentMSecsSinceEpoch());
            qInfo() << "[AppLaunchService] Spare runner ready, pid" << pid
                    << (shape == StorageSpare ? "(storage)" : "(plain)");
        }
    });
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            [this, proc, shape](int exitCode, QProcess::ExitStatus) {
                const qint64 pid   = proc->property("marathonPoolPid").toLongLong();
                Spare       &spare = m_spares[shape];
                if (proc == spare.process) {
                    // Only a spare that never got healthy counts against the
                    // retry budget. One that ran for a while and then died was
                    // working -- something outside took it: PSI/oomd reaping the
                    // idlest process (which is exactly what a warm spare looks
                    // like), or a tool that SIGTERMs every runner. Counting
                    // those was self-defeating: m_spareFailures only ever
                    // incremented, so three reaps over a long uptime disabled
                    // the pool for the rest of the session and silently put
                    // ~1s back onto every app launch until reboot.
                    const qint64 startedMs = proc->property("marathonSpareStartMs").toLongLong();
                    const qint64 livedMs =
                        startedMs > 0 ? QDateTime::currentMSecsSinceEpoch() - startedMs : 0;
                    const bool wasHealthy = livedMs >= kSpareHealthyMs;
                    qWarning() << "[AppLaunchService] Spare runner died unadopted, exit" << exitCode
                               << "after" << livedMs << "ms"
                               << (wasHealthy ? "(healthy - not counted)" : "(early - counted)")
                               << "healthyDeaths" << m_spareHealthyDeaths;
                    spare = {};
                    closeSandboxSocket(proc->property("marathonSandboxInstance").toString());
                    // A healthy death does not count against the budget, but it
                    // does not zero it either. Resetting would (a) let an
                    // intermittent broken spawn -- fail, fail, one long-lived
                    // death -- respawn forever without ever reaching the
                    // ceiling, and (b) turn the very case this exists for into
                    // a loop: oomd reaps the idle spare, we rebuild an mlockall
                    // 'd Qt runner 5s later, which restores the pressure that
                    // caused the kill. Back off instead, so repeated reaping
                    // costs progressively less.
                    int delayMs = 5000;
                    if (!wasHealthy) {
                        ++m_spareFailures;
                    } else {
                        ++m_spareHealthyDeaths;
                        delayMs = qMin(5000 << qMin(m_spareHealthyDeaths - 1, 5), 300000);
                        m_spareRetryAfterMs = QDateTime::currentMSecsSinceEpoch() + delayMs;
                    }
                    QTimer::singleShot(delayMs, this, &AppLaunchService::refillSpares);
                } else if (proc->property("marathonRetired").toBool()) {
                    closeSandboxSocket(proc->property("marathonSandboxInstance").toString());
                    QTimer::singleShot(kSpareRefillDelayMs, this, &AppLaunchService::refillSpares);
                } else if (pid > 0) {
                    onCompositorAppClosed(pid);
                }
                proc->deleteLater();
            });

    QStringList args = spareSandboxArgs(waylandSocket, shape);
    args << runnerExecutablePath() << QStringLiteral("--pool");
    m_spares[shape].process = proc;
    proc->start(bwrapPath, args);
    return true;
}

bool AppLaunchService::adoptSpareRunner(SpareShape shape, const PendingLaunch &p,
                                        const QVariantMap &env) {
    Spare &spare = m_spares[shape];
    if (!spare.adoptable || spare.process->state() != QProcess::Running)
        return false;
    QJsonObject envObj;
    {
        QSettings shellSettings(QSettings::IniFormat, QSettings::UserScope,
                                QStringLiteral("marathon-os"), QStringLiteral("Marathon Shell"));
        envObj.insert(
            QStringLiteral("MARATHON_USER_SCALE"),
            QString::number(
                shellSettings.value(QStringLiteral("ui/userScaleFactor"), 1.0).toDouble(), 'f', 3));
    }
    // The grants the app's own helpers check, such as marathon-mail-oauth.
    for (auto it = env.cbegin(); it != env.cend(); ++it) {
        if (it.key().startsWith(QLatin1String("MARATHON_PERM_")))
            envObj.insert(it.key(), it.value().toString());
    }
    QJsonObject msg;
    msg.insert(QStringLiteral("appId"), p.appId);
    msg.insert(QStringLiteral("route"), m_pendingRoute);
    msg.insert(QStringLiteral("routeParams"), m_pendingRouteParamsJson);
    msg.insert(QStringLiteral("env"), envObj);
    // Register before waking the spare: pidRegistered places the pid in its
    // cgroup and applies the foreground uclamp boost, so the adopt work runs
    // at interactive CPU frequency instead of ramping up from idle.
    PendingLaunch tracked   = p;
    tracked.pid             = spare.pid;
    tracked.sandboxInstance = spare.process->property("marathonSandboxInstance").toString();
    QMetaObject::invokeMethod(m_compositor.data(), "assignSandboxApp", Qt::DirectConnection,
                              Q_ARG(QString, tracked.sandboxInstance), Q_ARG(QString, p.appId));
    m_activeByPid.insert(spare.pid, tracked);
    registerPidForAppId(spare.pid, p.appId);

    const QByteArray line = QJsonDocument(msg).toJson(QJsonDocument::Compact) + '\n';
    if (spare.process->write(line) != line.size()) {
        qWarning() << "[AppLaunchService] Pool adopt write failed for" << p.appId;
        m_activeByPid.remove(tracked.pid);
        return false;
    }
    spare.process->setProperty("marathonAppId", p.appId);
    m_pendingRoute.clear();
    m_pendingRouteParamsJson.clear();
    qInfo() << "[AppLaunchService] Pool-adopted runner pid" << tracked.pid << "for" << p.appId;

    // Ownership stays with `this`; the finished handler set up at spawn
    // recognises the adopted process by pointer inequality with the spare.
    spare = {};
    // Refill once the adopted app has finished starting. A replacement
    // spare spends several seconds of CPU loading Qt, Mesa (with LLVM) and
    // the warm-up QML; spawned 1.5 s after adoption it competed with the
    // app's own startup on the PinePhone's four A53 cores. An app launched
    // within this window starts cold.
    QTimer::singleShot(kSpareRefillDelayMs, this, &AppLaunchService::refillSpares);
    return true;
}

bool AppLaunchService::invokeVoid(QObject *obj, const char *method, const QVariantList &args) {
    if (!obj)
        return false;
    switch (args.size()) {
        case 0: return QMetaObject::invokeMethod(obj, method, Qt::DirectConnection);
        case 1:
            return QMetaObject::invokeMethod(obj, method, Qt::DirectConnection,
                                             Q_ARG(QVariant, args.value(0)));
        case 2:
            return QMetaObject::invokeMethod(obj, method, Qt::DirectConnection,
                                             Q_ARG(QVariant, args.value(0)),
                                             Q_ARG(QVariant, args.value(1)));
        case 3:
            return QMetaObject::invokeMethod(
                obj, method, Qt::DirectConnection, Q_ARG(QVariant, args.value(0)),
                Q_ARG(QVariant, args.value(1)), Q_ARG(QVariant, args.value(2)));
        case 4:
            return QMetaObject::invokeMethod(
                obj, method, Qt::DirectConnection, Q_ARG(QVariant, args.value(0)),
                Q_ARG(QVariant, args.value(1)), Q_ARG(QVariant, args.value(2)),
                Q_ARG(QVariant, args.value(3)));
        case 5:
            return QMetaObject::invokeMethod(
                obj, method, Qt::DirectConnection, Q_ARG(QVariant, args.value(0)),
                Q_ARG(QVariant, args.value(1)), Q_ARG(QVariant, args.value(2)),
                Q_ARG(QVariant, args.value(3)), Q_ARG(QVariant, args.value(4)));
        default:
            return QMetaObject::invokeMethod(
                obj, method, Qt::DirectConnection, Q_ARG(QVariant, args.value(0)),
                Q_ARG(QVariant, args.value(1)), Q_ARG(QVariant, args.value(2)),
                Q_ARG(QVariant, args.value(3)), Q_ARG(QVariant, args.value(4)),
                Q_ARG(QVariant, args.value(5)));
    }
}

bool AppLaunchService::invokeBool(QObject *obj, const char *method, const QVariantList &args,
                                  bool *out) {
    if (!obj)
        return false;
    QVariant ret;
    auto     r  = Q_RETURN_ARG(QVariant, ret);
    bool     ok = false;
    switch (args.size()) {
        case 0: ok = QMetaObject::invokeMethod(obj, method, Qt::DirectConnection, r); break;
        case 1:
            ok = QMetaObject::invokeMethod(obj, method, Qt::DirectConnection, r,
                                           Q_ARG(QVariant, args.value(0)));
            break;
        case 2:
            ok = QMetaObject::invokeMethod(obj, method, Qt::DirectConnection, r,
                                           Q_ARG(QVariant, args.value(0)),
                                           Q_ARG(QVariant, args.value(1)));
            break;
        default:
            ok = QMetaObject::invokeMethod(
                obj, method, Qt::DirectConnection, r, Q_ARG(QVariant, args.value(0)),
                Q_ARG(QVariant, args.value(1)), Q_ARG(QVariant, args.value(2)));
            break;
    }
    if (ok && out)
        *out = ret.toBool();
    return ok;
}

void AppLaunchService::onCompositorAppLaunched(const QString &command, qint64 pid) {
    auto it = m_pendingByCommand.find(command);
    if (it == m_pendingByCommand.end()) {
        qInfo() << "[AppLaunchService] appLaunched:" << command << "PID" << pid << "(untracked)";
        return;
    }
    PendingLaunch p = it.value();
    p.pid           = pid;
    m_pendingByCommand.erase(it);
    m_activeByPid.insert(pid, p);
    m_pidToAppId.insert(pid, p.appId);
    m_appIdToPid.insert(p.appId, pid);
    qInfo() << "[AppLaunchService] appLaunched tracked:" << p.appId << "PID" << pid;
}

void AppLaunchService::onCompositorAppClosed(qint64 pid) {
    if (!m_activeByPid.contains(pid)) {
        qInfo() << "[AppLaunchService] appClosed PID" << pid << "(untracked)";
        return;
    }
    const PendingLaunch p = m_activeByPid.take(pid);
    closeSandboxSocket(p.sandboxInstance);
    m_pidToAppId.remove(pid);
    // The app's pid may be the sandbox's inner runner (matched by its
    // window), which died with the sandbox.
    const qint64 appPid = m_appIdToPid.value(p.appId, -1);
    if (appPid == pid || (appPid > 0 && !QFileInfo::exists(QStringLiteral("/proc/%1").arg(appPid)))) {
        m_appIdToPid.remove(p.appId);
        m_pidToAppId.remove(appPid);
        emit pidUnregistered(appPid, p.appId);
    }

    // Exited before any window: a launcher, unless no window comes.
    if (!m_windows.contains(p.appId) && !(m_taskModel && m_taskModel->getTaskByAppId(p.appId))) {
        qInfo() << "[AppLaunchService]" << p.appId << "launch PID" << pid
                << "exited before its window - waiting for one";
        m_exitedLaunches.insert(p.appId, p);
        QTimer::singleShot(m_exitedLaunchGraceMs, this, [this, appId = p.appId, pid]() {
            const auto it = m_exitedLaunches.constFind(appId);
            if (it == m_exitedLaunches.cend() || it->pid != pid)
                return;
            m_exitedLaunches.erase(it);
            finishAppExit(appId);
        });
        return;
    }
    finishAppExit(p.appId);
}

void AppLaunchService::finishAppExit(const QString &appId) {
    m_backgroundLaunches.remove(appId);
    if (m_taskModel) {
        if (Task *t = m_taskModel->getTaskByAppId(appId)) {
            m_taskModel->closeTask(t->id());
            qInfo() << "[AppLaunchService] Closed task for app" << appId << "on PID exit";
        }
    }

    if (m_appLifecycleManager) {
        QMetaObject::invokeMethod(m_appLifecycleManager, "unregisterApp", Qt::DirectConnection,
                                  Q_ARG(QString, appId));
    }

    emit appExited(appId);
}

QString AppLaunchService::appIdForPid(qint64 pid) const {
    return m_pidToAppId.value(pid, QString());
}

qint64 AppLaunchService::pidForAppId(const QString &appId) const {
    return m_appIdToPid.value(appId, -1);
}

void AppLaunchService::registerPidForAppId(qint64 pid, const QString &appId) {
    if (pid <= 0 || appId.isEmpty())
        return;
    m_pidToAppId.insert(pid, appId);
    m_appIdToPid.insert(appId, pid);
    emit pidRegistered(pid, appId);
}

bool AppLaunchService::isMarathonAppId(const QString &appId) const {
    if (!m_appModel)
        return false;
    if (App *a = m_appModel->getApp(appId))
        return a->type() == QStringLiteral("marathon");
    return false;
}

// The runner registers DBus service `org.marathonos.AppRunner.<appId>`
// (tools/marathon-app-runner/main.cpp ~L994 — the comment there spells
// out why: pid-based names collided across every running app and
// registration silently failed). The shell was NOT updated when the
// runner moved off pid-based names, so every sendBackToRunner /
// sendForwardToRunner call hit an invalid interface — the nav-bar
// back gesture appeared to ALWAYS minimize the foreground app
// instead of popping its subview stack, because handleSystemBack
// saw handled=false and the shell fell through to UIStore.closeApp().
//
// Sanitize appId the same way the runner does so an app id
// containing special characters maps to the same DBus name on
// both sides.
static QString sanitizedAppId(const QString &appId) {
    static const QRegularExpression nonAlnum(QStringLiteral("[^A-Za-z0-9_]"));
    return QString(appId).replace(nonAlnum, QStringLiteral("_"));
}

static QString runnerServiceNameForAppId(const QString &appId) {
    return QStringLiteral("org.marathonos.AppRunner.%1").arg(sanitizedAppId(appId));
}

// Must not block: this runs on the compositor thread, and the runner can be
// waiting on a frame callback that only this thread sends.
static QDBusPendingCall callRunnerLifecycle(const QString &appId, const char *method,
                                            const QVariantList &args = {}, int timeoutMs = -1) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        runnerServiceNameForAppId(appId), QStringLiteral("/org/marathonos/AppRunner/Lifecycle"),
        QStringLiteral("org.marathonos.AppRunner.Lifecycle1"), QString::fromLatin1(method));
    msg.setArguments(args);
    return QDBusConnection::sessionBus().asyncCall(msg, timeoutMs);
}

void AppLaunchService::sendBackToRunner(const QString &appId) {
    if (appId.isEmpty())
        return;
    auto *watcher = new QDBusPendingCallWatcher(callRunnerLifecycle(appId, "Back"), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, appId](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<bool> reply = *w;
        if (reply.isError() || !reply.value())
            emit runnerBackUnhandled(appId);
        w->deleteLater();
    });
}

void AppLaunchService::sendForwardToRunner(const QString &appId) {
    if (!appId.isEmpty())
        callRunnerLifecycle(appId, "Forward");
}

void AppLaunchService::setCoverVisible(const QString &appId, bool visible) {
    if (!appId.isEmpty())
        callRunnerLifecycle(appId, "SetCoverStatus", {visible ? 1 : 0});
}

bool AppLaunchService::servesKeelActions(const QString &appId) const {
    return !appId.isEmpty() &&
        !QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                QStringLiteral("keel/actions/org.marathonos.%1.json").arg(appId))
             .isEmpty();
}

void AppLaunchService::prepareRunnerFreeze(const QString &appId, QObject *context,
                                           const std::function<void()> &done) {
    auto *watcher =
        new QDBusPendingCallWatcher(callRunnerLifecycle(appId, "PrepareFreeze", {}, 1000), context);
    connect(watcher, &QDBusPendingCallWatcher::finished, context,
            [appId, done](QDBusPendingCallWatcher *w) {
                if (w->isError())
                    qWarning() << "[AppLaunchService] PrepareFreeze for" << appId
                               << "failed:" << w->error().message();
                w->deleteLater();
                done();
            });
}

void AppLaunchService::notifyRunnerThawed(const QString &appId) {
    callRunnerLifecycle(appId, "Thawed");
}

qint64 AppLaunchService::hostPidForAppId(const QString &appId) const {
    for (auto it = m_activeByPid.cbegin(); it != m_activeByPid.cend(); ++it) {
        if (it->appId == appId && SailfishLaunch::isHosted(it->command))
            return it.key();
    }
    return -1;
}

bool AppLaunchService::isKeelHostApp(const QString &appId) const {
    return hostPidForAppId(appId) > 0;
}

void AppLaunchService::setAppActive(const QString &appId, bool active) const {
    if (isKeelHostApp(appId))
        callRunnerLifecycle(appId, "SetActive", {active});
}

qint64 AppLaunchService::terminationPidForAppId(const QString &appId) const {
    const qint64 host = hostPidForAppId(appId);
    return host > 0 ? host : pidForAppId(appId);
}

#if defined(HAVE_WAYLAND)
void AppLaunchService::onCompositorSurfaceCreated(QWaylandSurface *surface, int surfaceId,
                                                  QWaylandXdgSurface *xdgSurface) {
    if (!surface) {
        qWarning() << "[AppLaunchService] surfaceCreated received null surface";
        return;
    }

    qint64 pid = -1;
    if (surface->client())
        pid = surface->client()->processId();

    QString xdgAppId;
    QString title;
    if (xdgSurface && xdgSurface->toplevel()) {
        xdgAppId = xdgSurface->toplevel()->appId();
        title    = xdgSurface->toplevel()->title();
    }

    QObject *qmlSurfaceObj =
        xdgSurface ? static_cast<QObject *>(xdgSurface) : static_cast<QObject *>(surface);

    // A sandboxed client is the app its sandbox says, whatever xdg app_id it
    // sets, and matches that app's launch even outside its process tree.
    const QString sandboxAppId = sandboxAppIdFor(surface);
    if (!sandboxAppId.isEmpty())
        xdgAppId = sandboxAppId;

    auto *wc         = qobject_cast<WaylandCompositor *>(m_compositor.data());
    bool  frontInput = false;
    if (wc && wc->recentUserInput(2000) && m_uiStore && m_taskModel &&
        m_uiStore->property("appWindowOpen").toBool()) {
        const Task *front = m_taskModel->getTaskByAppId(m_uiStore->property("currentAppId").toString());
        const auto *xdg   = front ? qobject_cast<QWaylandXdgSurface *>(front->waylandSurface()) : nullptr;
        frontInput = xdg && xdg->surface() && xdg->surface()->client() == surface->client();
    }
    const bool shown =
        mapWindow(pid, xdgAppId, title, sandboxAppId, surfaceId, qmlSurfaceObj, frontInput);
    // Read by the compositor: the window's first configure, and whether it
    // may be configured only to change something.
    surface->setProperty("mappedInBackground", !shown);
    const Task *task = m_taskModel ? m_taskModel->getTaskBySurfaceId(surfaceId) : nullptr;
    surface->setProperty("foreignClient", task && terminationPidForAppId(task->appId()) <= 0);
}
#endif

void AppLaunchService::expectWindow(const QString &appId) {
    m_expectedWindows.insert(appId, QDeadlineTimer(m_expectWindowMs));
    if (m_taskModel && m_taskModel->getTaskByAppId(appId))
        launchApp(QVariant(appId));
}

void AppLaunchService::setAppSecure(const QString &appId, bool secure) {
    if (secure == m_secureApps.contains(appId))
        return;
    if (secure)
        m_secureApps.insert(appId, m_taskModel && m_taskModel->getTaskByAppId(appId));
    else
        m_secureApps.remove(appId);
    emit secureAppsChanged();
}

bool AppLaunchService::mapWindow(qint64 pid, const QString &xdgAppId, const QString &title,
                                 const QString &sandboxAppId, int surfaceId,
                                 QObject *qmlSurfaceObj, bool frontInput) {
    if (const auto expected = m_expectedWindows.constFind(xdgAppId);
        expected != m_expectedWindows.cend()) {
        frontInput = frontInput || !expected->hasExpired();
        if (expected->hasExpired())
            m_expectedWindows.erase(expected);
    }
    // Android's own rule for starting an activity in front: in answer to the
    // user's input on the app in front.
    const auto takeFront = [this, surfaceId, qmlSurfaceObj](const QString &appId,
                                                             const QString &name,
                                                             const QString &icon) {
        if (m_uiStore)
            invokeVoid(m_uiStore, "openApp", {appId, name, icon});
        if (m_appWindow)
            invokeVoid(m_appWindow, "show",
                       {appId, name, icon, QStringLiteral("native"),
                        QVariant::fromValue(qmlSurfaceObj), surfaceId});
        return true;
    };
    const auto showLaunch = [this, surfaceId, qmlSurfaceObj](const PendingLaunch &p) {
        const QString type = p.type.isEmpty() ? QStringLiteral("native") : p.type;
        if (m_taskModel) {
            if (m_taskModel->getTaskByAppId(p.appId))
                m_taskModel->updateTaskNativeInfo(p.appId, surfaceId, qmlSurfaceObj);
            else
                m_taskModel->launchTask(p.appId, p.name, p.icon, type, surfaceId, qmlSurfaceObj);
        }
        fileWindow(p.appId, surfaceId, qmlSurfaceObj);
        if (m_backgroundLaunches.remove(p.appId))
            return false;
        if (m_appWindow)
            invokeVoid(m_appWindow, "show",
                       {p.appId, p.name, p.icon, type, QVariant::fromValue(qmlSurfaceObj),
                        surfaceId});
        return true;
    };

    if (pid > 0) {
        auto it = m_activeByPid.find(pid);
        if (it != m_activeByPid.end()) {
            const PendingLaunch &p = it.value();
            qInfo() << "[AppLaunchService] Matched surfaceId" << surfaceId << "to PID" << pid
                    << "app" << p.appId;
            // Seeds the lifecycle state and cgroup, as the child-process
            // match below does; a background launch stays in the background.
            if (m_backgroundLaunches.contains(p.appId) || p.type == QLatin1String("native"))
                registerPidForAppId(pid, p.appId);
            return showLaunch(p);
        }
    }

#ifdef Q_OS_LINUX
    if (pid > 0 && !m_activeByPid.isEmpty()) {
        for (auto it = m_activeByPid.constBegin(); it != m_activeByPid.constEnd(); ++it) {
            const qint64 parentPid = it.key();
            if (parentPid <= 0)
                continue;
            const bool sameSandbox = !sandboxAppId.isEmpty() && it->appId == sandboxAppId;
            if (!sameSandbox && !isDescendantPid(pid, parentPid))
                continue;

            const PendingLaunch &p = it.value();
            qInfo() << "[AppLaunchService] Matched surfaceId" << surfaceId << "to child PID" << pid
                    << "(ancestor PID" << parentPid << ", sandbox app" << sandboxAppId << ") app"
                    << p.appId;

            registerPidForAppId(pid, p.appId);
            return showLaunch(p);
        }
    }
#endif

    // Launched by another process (`waydroid app launch`), which is not the app.
    PendingLaunch launch = m_exitedLaunches.take(xdgAppId);
    for (auto it = m_pendingByCommand.begin(); !xdgAppId.isEmpty() && it != m_pendingByCommand.end();) {
        if (it->appId != xdgAppId) {
            ++it;
            continue;
        }
        launch = it.value();
        it     = m_pendingByCommand.erase(it);
    }
    for (auto it = m_activeByPid.begin(); !xdgAppId.isEmpty() && it != m_activeByPid.end();) {
        if (it->appId != xdgAppId) {
            ++it;
            continue;
        }
        launch = it.value();
        m_pidToAppId.remove(it.key());
        if (m_appIdToPid.value(xdgAppId) == it.key())
            m_appIdToPid.remove(xdgAppId);
        it = m_activeByPid.erase(it);
    }
    if (!launch.appId.isEmpty()) {
        qInfo() << "[AppLaunchService] Matched surfaceId" << surfaceId << "to the launch of"
                << xdgAppId << "by PID" << launch.pid << "- window from PID" << pid;
        return showLaunch(launch);
    }

    if (!xdgAppId.isEmpty() && m_taskModel && m_taskModel->getTaskByAppId(xdgAppId)) {
        qInfo() << "[AppLaunchService] Secondary surface for existing appId" << xdgAppId
                << "surfaceId" << surfaceId;
        m_taskModel->updateTaskNativeInfo(xdgAppId, surfaceId, qmlSurfaceObj);
        fileWindow(xdgAppId, surfaceId, qmlSurfaceObj);
        const Task *task = m_taskModel->getTaskByAppId(xdgAppId);
        return frontInput && takeFront(xdgAppId, task->title(), task->icon());
    }

    QString effectiveAppId = xdgAppId;
    if (effectiveAppId.isEmpty() && !title.isEmpty())
        effectiveAppId =
            "native-app-" + title.toLower().replace(nonSlug(), "-");
    if (effectiveAppId.isEmpty())
        effectiveAppId = QStringLiteral("native-surface-%1").arg(surfaceId);

    QString appName = !title.isEmpty() ? title : (!xdgAppId.isEmpty() ? xdgAppId : effectiveAppId);

    QString appIcon = !xdgAppId.isEmpty() ? xdgAppId : QStringLiteral("application-x-executable");
    if (m_appModel && !xdgAppId.isEmpty()) {
        if (App *a = m_appModel->getApp(xdgAppId)) {
            if (!a->icon().isEmpty())
                appIcon = a->icon();
        }
    }

    if (m_taskModel) {
        if (Task *existing = m_taskModel->getTaskByAppId(effectiveAppId)) {
            m_taskModel->updateTaskNativeInfo(effectiveAppId, surfaceId, qmlSurfaceObj);
        } else {
            m_taskModel->launchTask(effectiveAppId, appName, appIcon, "native", surfaceId,
                                    qmlSurfaceObj);
        }
    }
    fileWindow(effectiveAppId, surfaceId, qmlSurfaceObj);
    // Nobody launched it: a card. Waydroid re-creates a task's window as
    // Android redraws it, and that must not take the front.
    return frontInput && takeFront(effectiveAppId, appName, appIcon);
}

void AppLaunchService::fileWindow(const QString &appId, int surfaceId, QObject *surface) {
    for (QList<Window> &windows : m_windows)
        windows.removeIf([surfaceId](const Window &w) { return w.surfaceId == surfaceId; });
    m_windows[appId].append({surfaceId, surface});
}

// The app's card shows its newest window left; with none left, an app with
// no process of its own is gone after a grace, as Waydroid re-creates a
// task's window as Android redraws it (an app with a process shows its own
// close).
void AppLaunchService::onWindowDestroyed(int surfaceId) {
    for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
        QList<Window> &windows = it.value();
        if (!windows.removeIf([surfaceId](const Window &w) { return w.surfaceId == surfaceId; }))
            continue;
        windows.removeIf([](const Window &w) { return !w.surface; });
        const QString &appId = it.key();
        Task          *task  = m_taskModel ? m_taskModel->getTaskByAppId(appId) : nullptr;
        if (!windows.isEmpty()) {
            if (task && task->surfaceId() == surfaceId)
                m_taskModel->updateTaskNativeInfo(appId, windows.last().surfaceId,
                                                  windows.last().surface);
            return;
        }
        if ((!task || task->surfaceId() == surfaceId) && terminationPidForAppId(appId) <= 0) {
            // A new window within the grace takes the card over (mapWindow).
            QTimer::singleShot(m_windowGraceMs, this, [this, appId = QString(appId), surfaceId]() {
                Task *task = m_taskModel ? m_taskModel->getTaskByAppId(appId) : nullptr;
                if (m_windows.contains(appId) || (task && task->surfaceId() != surfaceId))
                    return;
                qInfo() << "[AppLaunchService] Last window of" << appId << "gone - closing it";
                if (task)
                    m_taskModel->closeTask(task->id());
                if (m_appLifecycleManager)
                    QMetaObject::invokeMethod(m_appLifecycleManager, "unregisterApp",
                                              Qt::DirectConnection, Q_ARG(QString, appId));
            });
        }
        m_windows.erase(it);
        return;
    }
}

#if defined(HAVE_WAYLAND)
QString AppLaunchService::sandboxAppIdFor(QWaylandSurface *surface) const {
    auto *wc = qobject_cast<WaylandCompositor *>(m_compositor.data());
    return wc && surface->client() ? wc->sandboxAppId(surface->client()->client()) : QString();
}

// Activated with its launch's token, a window is that launch's window, even
// if it was filed as another task when it mapped. Any other honoured
// activation brings the window's task to the front.
void AppLaunchService::onCompositorSurfaceActivated(int surfaceId, QWaylandXdgSurface *xdgSurface,
                                                    qint64 launchPid) {
    if (!m_taskModel)
        return;
    QObject   *surfaceObj = xdgSurface;
    Task      *task       = m_taskModel->getTaskBySurfaceId(surfaceId);
    const auto launch     = m_activeByPid.constFind(launchPid);
    if (launch != m_activeByPid.cend()) {
        if (task && task->appId() == launch->appId)
            return;
        qInfo() << "[AppLaunchService] surfaceId" << surfaceId << "activated with the token of"
                << launch->appId;
        if (task)
            m_taskModel->closeTask(task->id());
        const QString type = launch->type.isEmpty() ? QStringLiteral("native") : launch->type;
        if (m_taskModel->getTaskByAppId(launch->appId))
            m_taskModel->updateTaskNativeInfo(launch->appId, surfaceId, surfaceObj);
        else
            m_taskModel->launchTask(launch->appId, launch->name, launch->icon, type, surfaceId,
                                    surfaceObj);
        fileWindow(launch->appId, surfaceId, surfaceObj);
        if (!m_backgroundLaunches.remove(launch->appId) && m_appWindow)
            invokeVoid(m_appWindow, "show",
                       {launch->appId, launch->name, launch->icon, type,
                        QVariant::fromValue(surfaceObj), surfaceId});
        return;
    }
    if (!task)
        return;
    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {task->appId(), task->title(), task->icon()});
    invokeVoid(m_appWindow, "show",
               {task->appId(), task->title(), task->icon(), task->appType(),
                QVariant::fromValue(surfaceObj), surfaceId});
}
#endif

// The compositor's real app area once the shell has laid out; a client that
// starts at its final size never lays out twice on open.
QSize AppLaunchService::initialAppSize() const {
    if (m_compositor) {
        const QSize viewport = m_compositor->property("appViewportSize").toSize();
        if (viewport.width() > 0 && viewport.height() > 0)
            return viewport;
    }
    return {DeviceProfile::instance().runnerWidth(), DeviceProfile::instance().runnerHeight()};
}
