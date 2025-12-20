#include "applaunchservice.h"

#include "appmodel.h"
#include "taskmodel.h"

#include <QMetaObject>
#include <QVariant>
#include <QDebug>
#include <QJSValue>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>

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

    // Connect compositor signals in C++ (no more QML "pending app" glue).
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
    // Accept either a string appId or a JS object (QVariantMap / QJSValue / QObject*)
    // IMPORTANT: Check map/object types before QString conversion; Qt can consider many variants
    // "convertible" to QString, which would break object launches (e.g. quick actions).
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
                {"type", a->type()}, {"exec", a->exec()},
            };
        }

        // Fallback: running task (externally launched)
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

    // If a QObject was passed (e.g. App* from QML), try reading properties.
    if (QObject *obj = app.value<QObject *>()) {
        QVariantMap    out;
        const QVariant id = obj->property("id");
        out["id"]         = id;
        out["name"]       = obj->property("name");
        out["icon"]       = obj->property("icon");
        out["type"]       = obj->property("type");
        out["exec"]       = obj->property("exec");

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
            }
        }

        if (!out.value("id").isValid() || out.value("name").toString().isEmpty())
            return {};
        return out;
    }

    return {};
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

    // UI state (QML singleton)
    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    // Show splash screen (no surface yet)
    invokeVoid(appWindowRef, "show", {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
    emit appLaunchProgress(appId, 50);

    // Launch native app via compositor
    if (!exec.isEmpty()) {
        // Track the exact command we pass into launchApp(), then correlate to pid/surface.
        PendingLaunch p;
        p.appId   = appId;
        p.name    = name;
        p.icon    = icon;
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

bool AppLaunchService::launchMarathonApp(const QVariantMap &app, QObject * /*compositorRef*/,
                                         QObject           *appWindowRef) {
    const QString appId = app.value("id").toString();
    const QString name  = app.value("name").toString();
    const QString icon  = app.value("icon").toString();
    const QString type  = app.value("type").toString();

    // New architecture: run Marathon apps out-of-process via marathon-app-runner.
    // They become Wayland clients, just like other native apps.
    QObject *comp = m_compositor.data();
    if (!comp) {
        m_launchingApps.remove(appId);
        emit appLaunchFailed(appId, name, "Compositor not available");
        return false;
    }

    // Out-of-process apps are tracked via TaskModel once their surface arrives.
    // If we already have a native task with a live surface, just bring it to foreground.
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
    // Show splash (no surface yet). We render this app as a Wayland-embedded client.
    invokeVoid(appWindowRef, "show", {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
    emit appLaunchProgress(appId, 60);

    // Launch the out-of-process runner as a Wayland client (connects to our compositor socket).
    // Prefer the build-tree runner when developing; fall back to PATH lookup for installed setups.
    QString       runnerPath;
    const QDir    shellBinDir(QCoreApplication::applicationDirPath()); // .../build/shell
    const QString candidate =
        shellBinDir.filePath("../tools/marathon-app-runner/marathon-app-runner");
    if (QFileInfo::exists(candidate)) {
        runnerPath = candidate;
    } else {
        runnerPath = QStringLiteral("marathon-app-runner");
    }

    const QString cmd = QStringLiteral("%1 --app-id %2").arg(runnerPath, appId);

    // Track the runner command for pid/surface correlation.
    PendingLaunch p;
    p.appId   = appId;
    p.name    = name;
    p.icon    = icon;
    p.command = cmd;
    m_pendingByCommand.insert(cmd, p);

    const bool ok =
        QMetaObject::invokeMethod(comp, "launchApp", Qt::DirectConnection, Q_ARG(QString, cmd));
    if (!ok)
        qWarning() << "[AppLaunchService] Failed to invoke launchApp(QString) on compositor";

    m_launchingApps.remove(appId);
    emit appLaunchProgress(appId, 100);
    emit appLaunchCompleted(appId, name);
    return true;
}

bool AppLaunchService::invokeVoid(QObject *obj, const char *method, const QVariantList &args) {
    if (!obj)
        return false;
    // QMetaObject::invokeMethod requires the argument count to match the method signature.
    // QML functions keep their declared parameter count, so we must pass the right number.
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
    if (m_appIdToPid.value(p.appId) == pid)
        m_appIdToPid.remove(p.appId);

    // Close task when the process actually terminates (authoritative lifecycle).
    if (m_taskModel) {
        if (Task *t = m_taskModel->getTaskByAppId(p.appId)) {
            m_taskModel->closeTask(t->id());
            qInfo() << "[AppLaunchService] Closed task for app" << p.appId << "on PID exit";
        }
    }
}

QString AppLaunchService::appIdForPid(qint64 pid) const {
    return m_pidToAppId.value(pid, QString());
}

void AppLaunchService::registerPidForAppId(qint64 pid, const QString &appId) {
    if (pid <= 0 || appId.isEmpty())
        return;
    m_pidToAppId.insert(pid, appId);
    m_appIdToPid.insert(appId, pid);
}

bool AppLaunchService::isMarathonAppId(const QString &appId) const {
    if (!m_appModel)
        return false;
    if (App *a = m_appModel->getApp(appId))
        return a->type() == QStringLiteral("marathon");
    return false;
}

static QString runnerServiceNameForPid(qint64 pid) {
    // D-Bus well-known name elements cannot start with a digit, so prefix the PID.
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
    QDBusMessage r = iface.call(QString::fromLatin1(method));
    return r.type() != QDBusMessage::ErrorMessage;
}

bool AppLaunchService::sendBackToRunner(const QString &appId) {
    const qint64 pid = m_appIdToPid.value(appId, -1);
    return callRunnerLifecycle(pid, "Back");
}

bool AppLaunchService::sendForwardToRunner(const QString &appId) {
    const qint64 pid = m_appIdToPid.value(appId, -1);
    return callRunnerLifecycle(pid, "Forward");
}

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

    // Prefer passing the xdg surface object into QML so ShellSurfaceItem can access toplevel/configure.
    // QWaylandSurface alone is not enough for sizing/configure in our QML glue.
    QObject *qmlSurfaceObj =
        xdgSurface ? static_cast<QObject *>(xdgSurface) : static_cast<QObject *>(surface);

    // Case 1: match by PID (our launches)
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
                    m_taskModel->launchTask(p.appId, p.name, p.icon, "native", surfaceId,
                                            qmlSurfaceObj);
                }
            }

            // Ensure UI shows it (swap splash -> real surface)
            if (m_appWindow)
                invokeVoid(m_appWindow, "show",
                           {p.appId, p.name, p.icon, QStringLiteral("native"),
                            QVariant::fromValue(qmlSurfaceObj), surfaceId});
            return;
        }
    }

    // Case 2: secondary window for an existing task (match by xdg app_id)
    if (!xdgAppId.isEmpty() && m_taskModel) {
        if (Task *existing = m_taskModel->getTaskByAppId(xdgAppId)) {
            qInfo() << "[AppLaunchService] Secondary surface for existing appId" << xdgAppId
                    << "surfaceId" << surfaceId;
            m_taskModel->updateTaskNativeInfo(xdgAppId, surfaceId, qmlSurfaceObj);
            return;
        }
    }

    // Case 3: external launch — create a task based on appId/title (best-effort)
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
            // Prefer theme lookup by appId if present; otherwise use whatever AppModel provides.
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
