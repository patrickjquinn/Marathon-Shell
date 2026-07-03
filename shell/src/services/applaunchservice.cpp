#include "applaunchservice.h"

#include "appmodel.h"
#include "taskmodel.h"

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
#include <QJsonObject>
#include <QSettings>
#include <QGuiApplication>
#include <QScreen>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>

#if defined(HAVE_WAYLAND)
#include "wayland/waylandcompositor.h"
#include <QtWaylandCompositor/QWaylandClient>
#include <QtWaylandCompositor/QWaylandSurface>
#include <QtWaylandCompositor/QWaylandXdgSurface>
#include <QtWaylandCompositor/QWaylandXdgToplevel>
#endif

namespace {
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
    // `--no-sandbox` because chromium's namespace sandbox tries to
    // CLONE_NEW{USER,PID,IPC} inside our bwrap and EPERMs.
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
        "--no-sandbox "
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
}

AppLaunchService::AppLaunchService(AppModel *appModel, TaskModel *taskModel, QObject *parent)
    : QObject(parent)
    , m_appModel(appModel)
    , m_taskModel(taskModel) {
    // First spare spawns after shell boot settles; adopts refill on demand.
    QTimer::singleShot(8000, this, &AppLaunchService::spawnSpareRunner);
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
            QObject::connect(wc, &WaylandCompositor::appLaunched, this,
                             [this](const QString &command, qint64 pid) {
                                 onCompositorAppLaunched(command, pid);
                             });
            QObject::connect(wc, &WaylandCompositor::appClosed, this,
                             [this](qint64 pid) { onCompositorAppClosed(pid); });
            QObject::connect(
                wc, &WaylandCompositor::surfaceCreated, this,
                [this](QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface) {
                    onCompositorSurfaceCreated(surface, surfaceId, xdgSurface);
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

bool AppLaunchService::cancelLaunch(const QString &appId) {
    if (!m_launchingApps.contains(appId))
        return false;
    m_launchingApps.remove(appId);
    qInfo() << "[AppLaunchService] Cancelled launch for:" << appId;
    return true;
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
        if (!m_appModel) {
            qWarning() << "[AppLaunchService] AppModel not available";
            return {};
        }
        if (App *a = m_appModel->getApp(appId)) {
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
            for (const QVariant &v : rawPerms.toList())
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
    if (m_launchingApps.contains(appId) && !hasUsableSurface) {
        qWarning() << "[AppLaunchService] App already launching:" << appId;
        return false;
    }

    m_launchingApps.insert(appId);
    emit appLaunchStarted(appId, name);

    if (type == "native")
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

    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    invokeVoid(appWindowRef, "show", {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
    emit appLaunchProgress(appId, 50);

    if (!exec.isEmpty()) {
        PendingLaunch p;
        p.appId   = appId;
        p.name    = name;
        p.icon    = icon;
        p.type    = QStringLiteral("native");
        p.command = exec;
        m_pendingByCommand.insert(exec, p);

        const bool ok = QMetaObject::invokeMethod(compositorRef, "launchApp", Qt::DirectConnection,
                                                  Q_ARG(QString, exec));
        if (!ok)
            qWarning() << "[AppLaunchService] Failed to invoke launchApp(QString) on compositor";
    }

    m_launchingApps.remove(appId);
    emit appLaunchCompleted(appId, name);
    return true;
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

    if (m_taskModel) {
        if (Task *existing = m_taskModel->getTaskByAppId(appId)) {
            if (existing->appType() == "native" && existing->surfaceId() >= 0 &&
                existing->waylandSurface()) {
                if (m_uiStore)
                    invokeVoid(m_uiStore, "restoreApp", {appId, name, icon});

                invokeVoid(appWindowRef, "show",
                           {appId, name, icon, QStringLiteral("native"),
                            QVariant::fromValue(existing->waylandSurface()),
                            existing->surfaceId()});

                m_launchingApps.remove(appId);
                emit appLaunchCompleted(appId, name);
                return true;
            }
            // Marathon (QML) app already in the task model — bring it forward
            // instead of re-spawning. Without this, a tap on the task-switcher
            // card while the surface is still attaching spawned a parallel
            // bwrap + runner pair (two 75-100 MB clones for the same app).
            if (existing->surfaceId() >= 0 && existing->waylandSurface()) {
                qWarning() << "[AppLaunchService] Restore branch:" << appId << "surfaceId"
                           << existing->surfaceId() << "type" << existing->appType();
                if (m_uiStore)
                    invokeVoid(m_uiStore, "restoreApp", {appId, name, icon});
                invokeVoid(appWindowRef, "show",
                           {appId, name, icon, existing->appType(),
                            QVariant::fromValue(existing->waylandSurface()),
                            existing->surfaceId()});
                m_launchingApps.remove(appId);
                emit appLaunchCompleted(appId, name);
                return true;
            }
            qWarning() << "[AppLaunchService] Task without usable surface for" << appId
                       << "- surfaceId" << existing->surfaceId() << "- falling to cold spawn";
        }
    }

    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    emit appLaunchProgress(appId, 30);
    invokeVoid(
        appWindowRef, "show",
        {appId, name, icon, type.isEmpty() ? QStringLiteral("marathon") : type, QVariant(), -1});
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
        bool             ok     = false;
        const QByteArray forced = qgetenv("MARATHON_FORCE_DPI");
        double           dpi    = 160.0;
        if (!forced.isEmpty()) {
            const double v = forced.toDouble(&ok);
            if (ok && v > 0)
                dpi = v;
        }
        if (!ok) {
            const QScreen *screen = QGuiApplication::primaryScreen();
            dpi                   = screen ? screen->logicalDotsPerInch() : 160.0;
        }
        env.insert("MARATHON_DPI", QString::number(dpi, 'f', 1));

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
                   qEnvironmentVariable("QSG_ANTIALIASING_METHOD", "vertex"));

        // MSAA samples for layered items. 0 silences "Layer requested N
        // samples but multisample renderbuffers are not supported" on
        // etnaviv. Shell's main.cpp probes the GPU and exports the chosen
        // value; we forward whatever the shell decided.
        env.insert("MARATHON_LAYER_SAMPLES", qEnvironmentVariable("MARATHON_LAYER_SAMPLES", "0"));

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
        env.insert("LANG", qEnvironmentVariable("LANG", "en_US.UTF-8"));

        // GPU HDR gate. AppBackdropBlur and any future MultiEffect/Shader
        // sources that want linear-precise compositing read this — defaults
        // off so etnaviv (Librem 5) skips the RGBA16F renderbuffer path
        // that QRhi can't allocate on this GPU ("Attempted to set
        // unsupported texture format 8"). Inherit from shell env or
        // default 0.
        env.insert("MARATHON_GPU_HDR", qEnvironmentVariable("MARATHON_GPU_HDR", "0"));
    }

    QStringList permissions = app.value("permissions").toStringList();
    QStringList requiresQt  = app.value("requiresQtModules").toStringList();
    QString     manifestChromiumFlags;
    // resolveAppObject populates only id/name/icon/type/exec/permissions
    // from the App model -- the model never exposed requiresQtModules, so
    // every map that reaches this path has an empty requiresQt. The
    // !usesWebEngine branch below then adds --unshare-user-try to bwrap
    // unconditionally, which the kernel rejects when Chromium tries to
    // nest its own CLONE_NEWUSER, killing every WebEngine app with
    // SIGTRAP deep in libQt6WebEngineCore.so. Until the App model is
    // extended, fall back to a manifest read for the appId so the
    // sandbox shape matches what Chromium can survive.
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
        auto                                it    = manifestCache.constFind(appId);
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
            it = manifestCache.insert(appId, bits);
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
        manifestChromiumFlags.isEmpty() ? QString::fromLatin1(kDefaultChromiumFlags) :
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
        env.insert("QT_OPENGL", qEnvironmentVariable("QT_OPENGL", "es2"));
        // EGL_PLATFORM=wayland pins Mesa's _eglGetNativePlatform to the
        // wayland binding before native-display sniffing. Without it
        // Mesa's lookup order can pick up gbm/drm when both libraries
        // are linked, leading to surfaceless EGL contexts that don't
        // match the wayland-egl client surface the runner needs. Cheap
        // insurance against ambiguous Mesa platform discovery.
        env.insert("EGL_PLATFORM", QStringLiteral("wayland"));
        // Force Mesa to advertise OpenGL ES 2.0 as the highest version
        // through eglQueryString(EGL_CLIENT_APIS) and related capability
        // queries. Without this, Chromium's GPU init queries the EGL
        // display, sees etnaviv reports ES 2.0 already (HALTI0), but
        // STILL requests an ES 3.x context via EGL_CONTEXT_CLIENT_VERSION
        // because its internal cap probe assumed ES3-capable Mesa. Pinning
        // GLES_VERSION_OVERRIDE makes Mesa lie consistently: every cap
        // query says 2.0, Chromium's negotiation aligns.
        env.insert("MESA_GLES_VERSION_OVERRIDE", QStringLiteral("2.0"));
        env.insert("QTWEBENGINE_CHROMIUM_FLAGS", effectiveChromiumFlags);
        env.insert("QTWEBENGINE_DISABLE_SANDBOX", "1");
        // Force Mesa to use etnaviv directly instead of auto-probing
        // Zink first. Hard-set, not qEnvironmentVariable: greetd
        // currently exports MESA_LOADER_DRIVER_OVERRIDE=kmsro for the
        // shell, which is the legacy split-display winsys layer name.
        // Mesa 25.x removed `kmsro` as a standalone gallium driver
        // (etnaviv pulls in renderonly internally) — passing kmsro to
        // the runner gets it "Failed to create context" because no such
        // driver is loadable. The shell's env is wrong but not worth
        // fighting upstream; for the runner we want the renderer name.
        env.insert("MESA_LOADER_DRIVER_OVERRIDE", QStringLiteral("etnaviv"));
        env.insert("GBM_BACKEND", QStringLiteral("etnaviv"));
        env.insert("GALLIUM_DRIVER", QStringLiteral("etnaviv"));
        // Tell wayland-egl clients which DRM render node to allocate on,
        // in lieu of Qt Wayland Compositor advertising linux-dmabuf-v1 v4
        // feedback (Qt 6.11 docs still title the attribution page
        // "unstable v3"; the v4 main_device feedback event is what phoc
        // ships and what Mesa clients use to discover renderD128). Phosh
        // distributes this same env var as their workaround for
        // wlroots#3757.
        env.insert("WLR_RENDER_DRM_DEVICE",
                   qEnvironmentVariable("WLR_RENDER_DRM_DEVICE", "/dev/dri/renderD128"));
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

    // Warm pool: hand a pre-initialised runner this app instead of paying
    // exec + dynamic linking + Qt init on the critical path (~1s of the
    // ~2s tap-to-frame measured 2026-07-02). WebEngine apps keep the cold
    // path — their env and sandbox shape are per-app.
    if (!usesWebEngine && m_spareAdoptable && m_spareProcess &&
        m_spareProcess->state() == QProcess::Running) {
        PendingLaunch pooled;
        pooled.appId   = appId;
        pooled.name    = name;
        pooled.icon    = icon;
        pooled.type    = type.isEmpty() ? QStringLiteral("marathon") : type;
        pooled.command = QStringLiteral("pool-adopt ") + appId;
        if (adoptSpareRunner(pooled)) {
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
    //   - read-write bind : XDG_DATA_HOME/marathon-apps/<appId>            (data)
    //   - read-write bind : XDG_CACHE_HOME/marathon-apps/<appId>           (cache)
    //   - pass through    : XDG_RUNTIME_DIR (Wayland + user D-Bus sockets)
    //   - tmpfs           : everything else under /home, /tmp
    //   - no network namespace unless "network" permission granted
    //   - --die-with-parent so a hung sandbox can't outlive the shell
    const QString bwrapPath = QStandardPaths::findExecutable("bwrap");
    QString       cmd;
    if (!bwrapPath.isEmpty() && !qEnvironmentVariableIsSet("MARATHON_DISABLE_SANDBOX")) {
        const QString xdgRuntimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR", "/run/user/1000");
        const QString homeDir       = qEnvironmentVariable("HOME", "/home/user");
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

        // Chromium's zygote sandbox does its own CLONE_NEW{PID,USER,IPC,UTS,
        // NET,CGROUP} on every renderer + GPU + utility process. Nesting
        // those over bwrap-pre-unshared namespaces returns EPERM, Chromium
        // CHECKs in its sandbox setup, and the WebEngine app aborts with
        // SIGTRAP deep in libQt6WebEngineCore (the same backtrace every
        // time -- thread N → sandbox::policy::SandboxLinux::PreSpawnTarget
        // → CHECK). The right shape for WebEngine apps is: bwrap provides
        // ONLY the filesystem / device cage (--ro-bind /usr, --tmpfs /tmp,
        // --bind /run/user/1000, etc) and Chromium runs its own full
        // namespace sandbox inside that. Non-WebEngine apps still get the
        // belt-and-braces extra isolation layer.
        if (!usesWebEngine) {
            bwrapArgs << QStringLiteral("--unshare-pid") << QStringLiteral("--unshare-uts")
                      << QStringLiteral("--unshare-ipc") << QStringLiteral("--unshare-cgroup-try")
                      << QStringLiteral("--unshare-user-try");
            // Network namespace: only granted to apps with "network"
            // permission. WebEngine apps need network and can't have a net
            // unshare under bwrap anyway (Chromium re-unshares).
            if (!permissions.contains("network"))
                bwrapArgs << QStringLiteral("--unshare-net");
        }

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
                  << QStringLiteral("--dev-bind-try") << QStringLiteral("/dev/dri/renderD128")
                  << QStringLiteral("/dev/dri/renderD128")
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
                  << xdgRuntimeDir << xdgRuntimeDir;

        // Pass HOME as a tmpfs-mounted directory; apps can write to their
        // per-app data/cache paths only.
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("HOME") << homeDir
                  << QStringLiteral("--setenv") << QStringLiteral("XDG_DATA_HOME") << xdgDataHome
                  << QStringLiteral("--setenv") << QStringLiteral("XDG_CACHE_HOME") << xdgCacheHome
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
        {
            // Honour MARATHON_FORCE_DPI in the parent shell — that is the
            // value ScreenMetricsCpp uses for Constants.scaleFactor in the
            // shell, so apps must see the same number or chrome and app
            // content scale at different rates (e.g. 1.0 shell vs 1.2 app
            // on a dev host with EDID DPI 192).
            const QByteArray forced = qgetenv("MARATHON_FORCE_DPI");
            double           dpi    = 160.0;
            bool             ok     = false;
            if (!forced.isEmpty()) {
                const double v = forced.toDouble(&ok);
                if (ok && v > 0)
                    dpi = v;
            }
            if (!ok) {
                const QScreen *screen = QGuiApplication::primaryScreen();
                dpi                   = screen ? screen->logicalDotsPerInch() : 160.0;
            }
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_DPI")
                      << QString::number(dpi, 'f', 1);
        }
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
                  << qEnvironmentVariable("QSG_ANTIALIASING_METHOD", "vertex");
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_LAYER_SAMPLES")
                  << qEnvironmentVariable("MARATHON_LAYER_SAMPLES", "0");
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MARATHON_GPU_HDR")
                  << qEnvironmentVariable("MARATHON_GPU_HDR", "0");
        bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("LANG")
                  << qEnvironmentVariable("LANG", "en_US.UTF-8");

        // WebEngine GPU shape — see kDefaultChromiumFlags + the
        // un-sandboxed env block above for the full reasoning. QT_OPENGL
        // pins Qt's GL context request to GLES2 (etnaviv's only profile)
        // so QRhi comes up cleanly; ANGLE→native libGL handles the same
        // underneath for chromium.
        if (usesWebEngine) {
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QT_OPENGL")
                      << qEnvironmentVariable("QT_OPENGL", "es2");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QTWEBENGINE_DISABLE_SANDBOX")
                      << QStringLiteral("1");
            // Mirror the etnaviv / render-node hints from the un-sandboxed
            // env block above into the bwrap sandbox so spawned WebEngine
            // apps land on the right driver path.
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MESA_LOADER_DRIVER_OVERRIDE")
                      << QStringLiteral("etnaviv");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("GBM_BACKEND")
                      << QStringLiteral("etnaviv");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("GALLIUM_DRIVER")
                      << QStringLiteral("etnaviv");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("WLR_RENDER_DRM_DEVICE")
                      << qEnvironmentVariable("WLR_RENDER_DRM_DEVICE", "/dev/dri/renderD128");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("EGL_PLATFORM")
                      << QStringLiteral("wayland");
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("MESA_GLES_VERSION_OVERRIDE")
                      << QStringLiteral("2.0");
            // The chromium flags value contains spaces (multiple --foo=bar
            // tokens) and the cmd string we build here is re-parsed by
            // QProcess::splitCommand on the compositor side. Per Qt 6 docs
            // QProcess::splitCommand only recognises DOUBLE quotes — single
            // quotes pass through literally. Without quoting, splitCommand
            // chops the value into separate args and bwrap sees
            // `--disable-gpu` as its own flag — "bwrap: Unknown option
            // --disable-gpu" and the WebEngine app fails to launch. The
            // chromium flags value doesn't contain any double quotes itself
            // so wrapping is safe.
            bwrapArgs << QStringLiteral("--setenv") << QStringLiteral("QTWEBENGINE_CHROMIUM_FLAGS")
                      << QStringLiteral("\"") + effectiveChromiumFlags + QStringLiteral("\"");
        }

        cmd = bwrapPath + QStringLiteral(" ") + bwrapArgs.join(' ') + QStringLiteral(" ") +
            runnerPath + QStringLiteral(" --app-id ") + appId;
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
    p.type    = type.isEmpty() ? QStringLiteral("marathon") : type;
    p.command = cmd;
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
// pool-adopted first-party apps. WebEngine apps never adopt.
QStringList AppLaunchService::spareSandboxArgs() const {
    const QString xdgRuntimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR", "/run/user/1000");
    const QString homeDir       = qEnvironmentVariable("HOME", "/home/user");
    const QString xdgDataHome =
        qEnvironmentVariable("XDG_DATA_HOME", QStringLiteral("%1/.local/share").arg(homeDir));
    const QString xdgCacheHome =
        qEnvironmentVariable("XDG_CACHE_HOME", QStringLiteral("%1/.cache").arg(homeDir));
    const QString xdgConfigHome =
        qEnvironmentVariable("XDG_CONFIG_HOME", QStringLiteral("%1/.config").arg(homeDir));
    const QString dataDir   = xdgDataHome + QStringLiteral("/marathon-apps");
    const QString cacheDir  = xdgCacheHome + QStringLiteral("/marathon-apps");
    const QString configDir = xdgConfigHome + QStringLiteral("/marathon-apps");

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
         << QStringLiteral("/dev/dri/renderD128") << QStringLiteral("/dev/dri/renderD128")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys") << QStringLiteral("/sys")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys/dev/char")
         << QStringLiteral("/sys/dev/char") << QStringLiteral("--ro-bind-try")
         << QStringLiteral("/sys/class/drm") << QStringLiteral("/sys/class/drm")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys/devices")
         << QStringLiteral("/sys/devices") << QStringLiteral("--ro-bind-try")
         << QStringLiteral("/run/dbus") << QStringLiteral("/run/dbus")
         << QStringLiteral("--ro-bind-try") << QStringLiteral("/var/run/dbus")
         << QStringLiteral("/var/run/dbus") << QStringLiteral("--tmpfs") << QStringLiteral("/tmp")
         << QStringLiteral("--tmpfs") << QStringLiteral("/dev/shm") << QStringLiteral("--tmpfs")
         << homeDir << QStringLiteral("--ro-bind") << QStringLiteral("/usr/share/marathon-apps")
         << QStringLiteral("/usr/share/marathon-apps") << QStringLiteral("--ro-bind-try")
         << configDir << configDir << QStringLiteral("--bind") << dataDir << dataDir
         << QStringLiteral("--bind") << cacheDir << cacheDir << QStringLiteral("--bind")
         << xdgRuntimeDir << xdgRuntimeDir;

    args << QStringLiteral("--setenv") << QStringLiteral("HOME") << homeDir
         << QStringLiteral("--setenv") << QStringLiteral("XDG_DATA_HOME") << xdgDataHome
         << QStringLiteral("--setenv") << QStringLiteral("XDG_CACHE_HOME") << xdgCacheHome
         << QStringLiteral("--setenv") << QStringLiteral("XDG_CONFIG_HOME") << xdgConfigHome
         << QStringLiteral("--setenv") << QStringLiteral("MARATHON_SHELL_PID")
         << QString::number(QCoreApplication::applicationPid()) << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_SANDBOXED") << QStringLiteral("1");

    {
        const QByteArray forced = qgetenv("MARATHON_FORCE_DPI");
        double           dpi    = 160.0;
        bool             ok     = false;
        if (!forced.isEmpty()) {
            const double v = forced.toDouble(&ok);
            if (ok && v > 0)
                dpi = v;
        }
        if (!ok) {
            const QScreen *screen = QGuiApplication::primaryScreen();
            dpi                   = screen ? screen->logicalDotsPerInch() : 160.0;
        }
        args << QStringLiteral("--setenv") << QStringLiteral("MARATHON_DPI")
             << QString::number(dpi, 'f', 1);
    }
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
         << qEnvironmentVariable("QSG_ANTIALIASING_METHOD", "vertex") << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_LAYER_SAMPLES")
         << qEnvironmentVariable("MARATHON_LAYER_SAMPLES", "0") << QStringLiteral("--setenv")
         << QStringLiteral("MARATHON_GPU_HDR") << qEnvironmentVariable("MARATHON_GPU_HDR", "0")
         << QStringLiteral("--setenv") << QStringLiteral("LANG")
         << qEnvironmentVariable("LANG", "en_US.UTF-8");

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

void AppLaunchService::spawnSpareRunner() {
    if (m_spareProcess)
        return;
    // Opt-in (MARATHON_RUNNER_POOL=1): measured 2026-07-02, the v1 pool
    // LOSES to cold launch (2.3-3.0s vs 2.0s tap-to-frame) — the idle
    // spare's pages get evicted while it waits and adoption pays them
    // back. Stays off until the spare is kept resident (mlock/periodic
    // touch) or the pool point moves past engine+import init.
    if (qEnvironmentVariableIntValue("MARATHON_RUNNER_POOL") != 1)
        return;
    if (m_spareFailures >= 3) {
        qWarning() << "[AppLaunchService] Runner pool disabled after repeated spare failures";
        return;
    }
    const QString bwrapPath = QStandardPaths::findExecutable("bwrap");
    if (bwrapPath.isEmpty() || qEnvironmentVariableIsSet("MARATHON_DISABLE_SANDBOX"))
        return; // pool covers the sandboxed production path only

    const QString homeDir = qEnvironmentVariable("HOME", "/home/user");
    QDir().mkpath(
        qEnvironmentVariable("XDG_DATA_HOME", QStringLiteral("%1/.local/share").arg(homeDir)) +
        QStringLiteral("/marathon-apps"));
    QDir().mkpath(qEnvironmentVariable("XDG_CACHE_HOME", QStringLiteral("%1/.cache").arg(homeDir)) +
                  QStringLiteral("/marathon-apps"));

    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::SeparateChannels);
    connect(proc, &QProcess::readyReadStandardError, this, [proc]() {
        const QStringList lines = QString::fromLocal8Bit(proc->readAllStandardError()).split('\n');
        for (const QString &l : lines) {
            const QString line = l.trimmed();
            if (!line.isEmpty())
                qWarning().noquote() << "[PoolRunner stderr]" << line;
        }
    });
    connect(proc, &QProcess::started, this, [this, proc]() {
        const qint64 pid = proc->processId();
        proc->setProperty("marathonPoolPid", pid);
        if (proc == m_spareProcess) {
            m_sparePid       = pid;
            m_spareAdoptable = true;
            qInfo() << "[AppLaunchService] Spare runner ready, pid" << pid;
        }
    });
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            [this, proc](int exitCode, QProcess::ExitStatus) {
                const qint64 pid = proc->property("marathonPoolPid").toLongLong();
                if (proc == m_spareProcess) {
                    qWarning() << "[AppLaunchService] Spare runner died unadopted, exit"
                               << exitCode;
                    m_spareProcess   = nullptr;
                    m_sparePid       = -1;
                    m_spareAdoptable = false;
                    ++m_spareFailures;
                    QTimer::singleShot(5000, this, &AppLaunchService::spawnSpareRunner);
                } else if (pid > 0) {
                    onCompositorAppClosed(pid);
                }
                proc->deleteLater();
            });

    QStringList args = spareSandboxArgs();
    args << runnerExecutablePath() << QStringLiteral("--pool");
    m_spareProcess = proc;
    proc->start(bwrapPath, args);
}

bool AppLaunchService::adoptSpareRunner(const PendingLaunch &p) {
    QJsonObject envObj;
    {
        QSettings shellSettings(QSettings::IniFormat, QSettings::UserScope,
                                QStringLiteral("marathon-os"), QStringLiteral("Marathon Shell"));
        envObj.insert(
            QStringLiteral("MARATHON_USER_SCALE"),
            QString::number(
                shellSettings.value(QStringLiteral("ui/userScaleFactor"), 1.0).toDouble(), 'f', 3));
    }
    QJsonObject msg;
    msg.insert(QStringLiteral("appId"), p.appId);
    msg.insert(QStringLiteral("route"), m_pendingRoute);
    msg.insert(QStringLiteral("routeParams"), m_pendingRouteParamsJson);
    msg.insert(QStringLiteral("env"), envObj);
    // Register before waking the spare: pidRegistered places the pid in its
    // cgroup and applies the foreground uclamp boost, so the adopt work runs
    // at interactive CPU frequency instead of ramping up from idle.
    PendingLaunch tracked = p;
    tracked.pid           = m_sparePid;
    m_activeByPid.insert(m_sparePid, tracked);
    registerPidForAppId(m_sparePid, p.appId);

    const QByteArray line = QJsonDocument(msg).toJson(QJsonDocument::Compact) + '\n';
    if (m_spareProcess->write(line) != line.size()) {
        qWarning() << "[AppLaunchService] Pool adopt write failed for" << p.appId;
        m_activeByPid.remove(tracked.pid);
        return false;
    }
    m_pendingRoute.clear();
    m_pendingRouteParamsJson.clear();
    qInfo() << "[AppLaunchService] Pool-adopted runner pid" << tracked.pid << "for" << p.appId;

    // Ownership stays with `this`; the finished handler set up at spawn
    // recognises the adopted process by pointer inequality with the spare.
    m_spareProcess   = nullptr;
    m_sparePid       = -1;
    m_spareAdoptable = false;
    QTimer::singleShot(1500, this, &AppLaunchService::spawnSpareRunner);
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
    auto it = m_activeByPid.find(pid);
    if (it == m_activeByPid.end()) {
        qInfo() << "[AppLaunchService] appClosed PID" << pid << "(untracked)";
        return;
    }
    const PendingLaunch &p = it.value();
    m_activeByPid.erase(it);
    m_pidToAppId.remove(pid);
    if (m_appIdToPid.value(p.appId) == pid) {
        m_appIdToPid.remove(p.appId);
        emit pidUnregistered(pid, p.appId);
    }

    if (m_taskModel) {
        if (Task *t = m_taskModel->getTaskByAppId(p.appId)) {
            m_taskModel->closeTask(t->id());
            qInfo() << "[AppLaunchService] Closed task for app" << p.appId << "on PID exit";
        }
    }

    if (m_appLifecycleManager) {
        QMetaObject::invokeMethod(m_appLifecycleManager, "unregisterApp", Qt::DirectConnection,
                                  Q_ARG(QString, p.appId));
    }

    emit appExited(p.appId);
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

static bool callRunnerLifecycle(const QString &appId, const char *method) {
    if (appId.isEmpty())
        return false;
    QDBusInterface iface(
        runnerServiceNameForAppId(appId), QStringLiteral("/org/marathonos/AppRunner/Lifecycle"),
        QStringLiteral("org.marathonos.AppRunner.Lifecycle1"), QDBusConnection::sessionBus());
    if (!iface.isValid())
        return false;
    QDBusReply<bool> r = iface.call(QString::fromLatin1(method));
    if (!r.isValid())
        return false;
    return r.value();
}

bool AppLaunchService::sendBackToRunner(const QString &appId) {
    return callRunnerLifecycle(appId, "Back");
}

bool AppLaunchService::sendForwardToRunner(const QString &appId) {
    return callRunnerLifecycle(appId, "Forward");
}

#ifdef Q_OS_LINUX
static bool isDescendantPid(qint64 childPid, qint64 ancestorPid) {
    if (childPid <= 0 || ancestorPid <= 0)
        return false;
    if (childPid == ancestorPid)
        return true;

    qint64 current = childPid;
    for (int i = 0; i < 128 && current > 1; ++i) {
        QFile statFile(QStringLiteral("/proc/%1/stat").arg(current));
        if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text))
            return false;
        const QByteArray statLine = statFile.readAll();
        const qsizetype  closeIdx = statLine.lastIndexOf(')');
        if (closeIdx < 0)
            return false;
        const QByteArray        after = statLine.mid(closeIdx + 1).trimmed();
        const QList<QByteArray> parts = after.split(' ');
        if (parts.size() < 2)
            return false;
        const qint64 ppid = parts.at(1).toLongLong();
        if (ppid == ancestorPid)
            return true;
        if (ppid <= 1)
            return false;
        current = ppid;
    }
    return false;
}
#endif

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

    if (pid > 0) {
        auto it = m_activeByPid.find(pid);
        if (it != m_activeByPid.end()) {
            const PendingLaunch &p = it.value();
            qInfo() << "[AppLaunchService] Matched surfaceId" << surfaceId << "to PID" << pid
                    << "app" << p.appId;

            if (m_taskModel) {
                if (Task *existing = m_taskModel->getTaskByAppId(p.appId)) {
                    m_taskModel->updateTaskNativeInfo(p.appId, surfaceId, qmlSurfaceObj);
                } else {
                    m_taskModel->launchTask(p.appId, p.name, p.icon,
                                            p.type.isEmpty() ? QStringLiteral("native") : p.type,
                                            surfaceId, qmlSurfaceObj);
                }
            }

            if (m_appWindow)
                invokeVoid(m_appWindow, "show",
                           {p.appId, p.name, p.icon,
                            p.type.isEmpty() ? QStringLiteral("native") : p.type,
                            QVariant::fromValue(qmlSurfaceObj), surfaceId});
            return;
        }
    }

#ifdef Q_OS_LINUX
    if (pid > 0 && !m_activeByPid.isEmpty()) {
        for (auto it = m_activeByPid.constBegin(); it != m_activeByPid.constEnd(); ++it) {
            const qint64 parentPid = it.key();
            if (parentPid <= 0)
                continue;
            if (!isDescendantPid(pid, parentPid))
                continue;

            const PendingLaunch &p = it.value();
            qInfo() << "[AppLaunchService] Matched surfaceId" << surfaceId << "to child PID" << pid
                    << "(ancestor PID" << parentPid << ") app" << p.appId;

            registerPidForAppId(pid, p.appId);

            if (m_taskModel) {
                if (Task *existing = m_taskModel->getTaskByAppId(p.appId)) {
                    m_taskModel->updateTaskNativeInfo(p.appId, surfaceId, qmlSurfaceObj);
                } else {
                    m_taskModel->launchTask(p.appId, p.name, p.icon,
                                            p.type.isEmpty() ? QStringLiteral("native") : p.type,
                                            surfaceId, qmlSurfaceObj);
                }
            }

            if (m_appWindow)
                invokeVoid(m_appWindow, "show",
                           {p.appId, p.name, p.icon,
                            p.type.isEmpty() ? QStringLiteral("native") : p.type,
                            QVariant::fromValue(qmlSurfaceObj), surfaceId});
            return;
        }
    }
#endif

    if (!xdgAppId.isEmpty() && m_taskModel) {
        if (Task *existing = m_taskModel->getTaskByAppId(xdgAppId)) {
            qInfo() << "[AppLaunchService] Secondary surface for existing appId" << xdgAppId
                    << "surfaceId" << surfaceId;
            m_taskModel->updateTaskNativeInfo(xdgAppId, surfaceId, qmlSurfaceObj);
            return;
        }
    }

    QString effectiveAppId = xdgAppId;
    if (effectiveAppId.isEmpty() && !title.isEmpty())
        effectiveAppId =
            "native-app-" + title.toLower().replace(QRegularExpression("[^a-z0-9]+"), "-");
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

    if (m_appWindow)
        invokeVoid(m_appWindow, "show",
                   {effectiveAppId, appName, appIcon, QStringLiteral("native"),
                    QVariant::fromValue(qmlSurfaceObj), surfaceId});
}
