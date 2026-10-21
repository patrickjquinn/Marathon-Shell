#include "applaunchservice.h"
#include "marathonapppaths.h"

#include "marathon-shell-native/src/apps.cxxqt.h"
#include "processtree.h"
#include "marathon-shell-native/src/desktop.cxxqt.h"
#include "marathon-shell-native/src/sandbox.cxxqt.h"
#include "taskmodel.h"
#include "src/managers/deviceprofile.h"
#include "src/managers/screenmetrics.h"

#include <QMetaObject>
#include <QVariant>
#include <QDebug>
#include <QJSValue>
#include <QCoreApplication>
#include <QDir>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QDateTime>
#include <QJsonObject>
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
#include "wayland/foreignfocus.h"
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

QString newSandboxInstance() {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

// The runner to start for appId, or a spare (empty appId) of that shape.
marathon::sandbox::Runner runnerFor(const QString &appId, const QStringList &permissions,
                                    const QStringList &requiresQt, bool storageSpare, QSize appSize,
                                    qreal userScale) {
    const QScreen *screen = QGuiApplication::primaryScreen();
    return {appId,
            permissions,
            requiresQt,
            storageSpare,
            QString(),
            DeviceProfile::instance().renderNode(),
            DeviceProfile::instance().gpuStack() == QLatin1String("mesa-v3d"),
            QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
                QStringLiteral("/marathon/thumbnails"),
            shellDpi(),
            userScale,
            screen ? screen->geometry().width() : 0,
            screen ? screen->geometry().height() : 0,
            appSize.width(),
            appSize.height()};
}
}

AppLaunchService::AppLaunchService(Apps *appModel, TaskModel *taskModel, QObject *parent)
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

int AppLaunchService::closeAppWindows(const QString &appId) {
    int                 closed  = 0;
    const QList<Window> windows = m_windows.value(appId);
    for (const Window &window : windows) {
        if (window.surface) {
            closeNativeApp(window.surfaceId);
            ++closed;
        }
    }
    return closed;
}

bool AppLaunchService::canLaunch(const QString &appId) const {
    return !resolveAppObject(appId).isEmpty();
}

QVariantMap AppLaunchService::resolveAppObject(const QVariant &app) const {
    if (app.typeId() == QMetaType::QVariantMap) {
        QVariantMap   out   = app.toMap();
        const QString appId = out.value("id").toString();
        if (!appId.isEmpty() && m_appModel) {
            if (const QVariantMap a = m_appModel->findById(appId); !a.isEmpty()) {
                if (out.value("name").toString().isEmpty())
                    out["name"] = a.value("name").toString();
                if (out.value("icon").toString().isEmpty())
                    out["icon"] = a.value("icon").toString();
                if (out.value("type").toString().isEmpty())
                    out["type"] = a.value("type").toString();
                if (out.value("exec").toString().isEmpty())
                    out["exec"] = a.value("exec").toString();
                if (out.value("permissions").toStringList().isEmpty())
                    out["permissions"] = a.value("permissions").toStringList();
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
        if (const QVariantMap a = m_appModel ? m_appModel->findById(appId) : QVariantMap(); !a.isEmpty()) {
            return {
                {"id", a.value("id").toString()},     {"name", a.value("name").toString()}, {"icon", a.value("icon").toString()},
                {"type", a.value("type").toString()}, {"exec", a.value("exec").toString()}, {"permissions", a.value("permissions").toStringList()},
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
            return marathon::desktop::parse(entry);

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
            if (const QVariantMap a = m_appModel->findById(appId); !a.isEmpty()) {
                if (out.value("name").toString().isEmpty())
                    out["name"] = a.value("name").toString();
                if (out.value("icon").toString().isEmpty())
                    out["icon"] = a.value("icon").toString();
                if (out.value("type").toString().isEmpty())
                    out["type"] = a.value("type").toString();
                if (out.value("exec").toString().isEmpty())
                    out["exec"] = a.value("exec").toString();
                if (perms.isEmpty())
                    perms = a.value("permissions").toStringList();
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

    const QStringList permissions = app.value("permissions").toStringList();
    marathon::sandbox::Runner runner =
        runnerFor(appId, permissions, app.value("requiresQtModules").toStringList(), false,
                  initialAppSize(), m_userScale);
    const bool        usesWebEngine = marathon::sandbox::uses_webengine(runner);
    QVariantMap       env           = marathon::sandbox::environment(runner);
    const bool        userInstalled = marathon::sandbox::is_user_installed(appId);

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

    QString sandboxInstance;
    if (!marathon::sandbox::bwrap().isEmpty()) {
        sandboxInstance       = newSandboxInstance();
        runner.wayland_socket = openSandboxSocket(appId, sandboxInstance);
        if (runner.wayland_socket.isEmpty()) {
            qWarning() << "[AppLaunchService] No sandbox Wayland socket for" << appId
                       << "- not launching";
            m_launchingApps.remove(appId);
            emit appLaunchFailed(appId, name, "No sandbox Wayland socket");
            return false;
        }
    }
    QString cmd =
        marathon::sandbox::command_line(marathon::sandbox::argv(runner, runnerExecutablePath()));

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

QString AppLaunchService::runnerExecutablePath() const {
    const QDir shellBinDir(QCoreApplication::applicationDirPath());
    QString    candidate = shellBinDir.filePath("../tools/marathon-app-runner/marathon-app-runner");
    if (QFileInfo::exists(candidate))
        return candidate;
    return QStringLiteral("marathon-app-runner");
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
    if (marathon::sandbox::bwrap().isEmpty())
        return false; // pool covers the sandboxed production path only

    // The spare's app is unknown until adoption; assignSandboxApp names it.
    marathon::sandbox::Runner runner =
        runnerFor(QString(), {}, {}, shape == StorageSpare, initialAppSize(), m_userScale);
    const QString instance = newSandboxInstance();
    runner.wayland_socket  = openSandboxSocket(QString(), instance);
    if (runner.wayland_socket.isEmpty())
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

    const QStringList argv  = marathon::sandbox::argv(runner, runnerExecutablePath());
    m_spares[shape].process = proc;
    proc->start(argv.first(), argv.mid(1));
    return true;
}

bool AppLaunchService::adoptSpareRunner(SpareShape shape, const PendingLaunch &p,
                                        const QVariantMap &env) {
    Spare &spare = m_spares[shape];
    if (!spare.adoptable || spare.process->state() != QProcess::Running)
        return false;
    QJsonObject envObj;
    envObj.insert(QStringLiteral("MARATHON_USER_SCALE"), QString::number(m_userScale, 'f', 3));
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
    if (const QVariantMap a = m_appModel->findById(appId); !a.isEmpty())
        return a.value("type").toString() == QStringLiteral("marathon");
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
        if (it->appId == appId && marathon::desktop::is_keel_hosted(it->command))
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
    if (!shown && wc && ForeignFocus::keepFront(wc->defaultSeat(), surface))
        qInfo() << "[AppLaunchService]" << xdgAppId
                << "mapped behind the window in front; entered that window again";
}
#endif

bool AppLaunchService::expectWindow(const QString &appId) {
    m_expectedWindows.insert(appId, QDeadlineTimer(m_expectWindowMs));
    const Task *task = m_taskModel ? m_taskModel->getTaskByAppId(appId) : nullptr;
    if (!task || task->surfaceId() < 0 || !task->waylandSurface())
        return false;
    launchApp(QVariant(appId));
    return true;
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
        if (const QVariantMap a = m_appModel->findById(xdgAppId); !a.isEmpty()) {
            if (!a.value("icon").toString().isEmpty())
                appIcon = a.value("icon").toString();
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
