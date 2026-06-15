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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QGuiApplication>
#include <QScreen>
#include <QFileInfo>
#include <QStandardPaths>
#include <QRegularExpression>
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

AppLaunchService::AppLaunchService(AppModel *appModel, TaskModel *taskModel, QObject *parent)
    : QObject(parent)
    , m_appModel(appModel)
    , m_taskModel(taskModel) {}

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
        qWarning() << "[AppLaunchService] Invalid app object";
        emit appLaunchFailed(appId, name, "Invalid app object");
        return false;
    }
    if (m_launchingApps.contains(appId)) {
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
        }
    }

    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    emit appLaunchProgress(appId, 30);
    invokeVoid(
        appWindowRef, "show",
        {appId, name, icon, type.isEmpty() ? QStringLiteral("marathon") : type, QVariant(), -1});
    emit          appLaunchProgress(appId, 60);

    QString       runnerPath;
    const QDir    shellBinDir(QCoreApplication::applicationDirPath());
    const QString candidate =
        shellBinDir.filePath("../tools/marathon-app-runner/marathon-app-runner");
    if (QFileInfo::exists(candidate)) {
        runnerPath = candidate;
    } else {
        runnerPath = QStringLiteral("marathon-app-runner");
    }

    QVariantMap env;
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
    }

    QStringList permissions = app.value("permissions").toStringList();
    QStringList requiresQt  = app.value("requiresQtModules").toStringList();
    // resolveAppObject populates only id/name/icon/type/exec/permissions
    // from the App model -- the model never exposed requiresQtModules, so
    // every map that reaches this path has an empty requiresQt. The
    // !usesWebEngine branch below then adds --unshare-user-try to bwrap
    // unconditionally, which the kernel rejects when Chromium tries to
    // nest its own CLONE_NEWUSER, killing every WebEngine app with
    // SIGTRAP deep in libQt6WebEngineCore.so. Until the App model is
    // extended, fall back to a manifest read for the appId so the
    // sandbox shape matches what Chromium can survive.
    if (requiresQt.isEmpty()) {
        const QString appId = app.value("id").toString();
        QFile         mf(QStringLiteral("/usr/share/marathon-apps/%1/manifest.json").arg(appId));
        if (mf.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(mf.readAll());
            const auto    arr = doc.object().value(QStringLiteral("requiresQtModules")).toArray();
            for (const auto &v : arr)
                requiresQt << v.toString();
        }
    }
    const bool usesWebEngine = requiresQt.contains(QStringLiteral("webengine"));

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
                  << QStringLiteral("/proc") << QStringLiteral("--dev") << QStringLiteral("/dev")
                  << QStringLiteral("--dev-bind-try") << QStringLiteral("/dev/dri")
                  << QStringLiteral("/dev/dri")
                  // /sys is needed for GPU/DRM driver discovery: Mesa walks
                  // /sys/dev/char/<major:minor> → /sys/class/drm/renderD128
                  // → /sys/devices/.../pci... to pick the right DRI driver.
                  // Without it Mesa logs "failed to retrieve device
                  // information" and falls back to zink/swrast.
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys")
                  << QStringLiteral("/sys")
                  // System D-Bus socket lives at /run/dbus/system_bus_socket
                  // (Alpine path; older distros at /var/run/dbus). Apps
                  // need it to reach ModemManager / NetworkManager / UPower
                  // / Bluez. Without this the runner logs
                  // "Failed to connect to socket /run/dbus/system_bus_socket".
                  << QStringLiteral("--ro-bind-try") << QStringLiteral("/run/dbus")
                  << QStringLiteral("/run/dbus") << QStringLiteral("--ro-bind-try")
                  << QStringLiteral("/var/run/dbus") << QStringLiteral("/var/run/dbus")
                  << QStringLiteral("--tmpfs") << QStringLiteral("/tmp")
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

    m_launchingApps.remove(appId);
    emit appLaunchProgress(appId, 100);
    emit appLaunchCompleted(appId, name);
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

static QString runnerServiceNameForPid(qint64 pid) {
    return QStringLiteral("org.marathonos.AppRunner.pid%1").arg(pid);
}

static bool callRunnerLifecycle(qint64 pid, const char *method) {
    if (pid <= 0)
        return false;
    QDBusInterface iface(
        runnerServiceNameForPid(pid), QStringLiteral("/org/marathonos/AppRunner/Lifecycle"),
        QStringLiteral("org.marathonos.AppRunner.Lifecycle1"), QDBusConnection::sessionBus());
    if (!iface.isValid())
        return false;
    QDBusReply<bool> r = iface.call(QString::fromLatin1(method));
    if (!r.isValid())
        return false;
    return r.value();
}

bool AppLaunchService::sendBackToRunner(const QString &appId) {
    const qint64 pid = m_appIdToPid.value(appId, -1);
    return callRunnerLifecycle(pid, "Back");
}

bool AppLaunchService::sendForwardToRunner(const QString &appId) {
    const qint64 pid = m_appIdToPid.value(appId, -1);
    return callRunnerLifecycle(pid, "Forward");
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
