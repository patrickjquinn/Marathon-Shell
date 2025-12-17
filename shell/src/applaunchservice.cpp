#include "applaunchservice.h"

#include "appmodel.h"
#include "taskmodel.h"

#include <QMetaObject>
#include <QVariant>
#include <QDebug>
#include <QJSValue>

AppLaunchService::AppLaunchService(AppModel *appModel, TaskModel *taskModel, QObject *parent)
    : QObject(parent)
    , m_appModel(appModel)
    , m_taskModel(taskModel) {}

void AppLaunchService::setCompositor(QObject *obj) {
    if (m_compositor == obj)
        return;
    m_compositor = obj;
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

    m_pendingNativeApp = app;
    emit pendingNativeAppChanged();

    // UI state (QML singleton)
    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    // Show splash screen (no surface yet)
    invokeVoid(appWindowRef, "show", {appId, name, icon, QStringLiteral("native"), QVariant(), -1});
    emit appLaunchProgress(appId, 50);

    // Launch native app via compositor
    if (!exec.isEmpty()) {
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

    // If app is already running, bring it forward and restore UI
    bool isRunning = false;
    if (m_appLifecycleManager) {
        bool       isRunningRet = false;
        const bool ok =
            QMetaObject::invokeMethod(m_appLifecycleManager, "isAppRunning", Qt::DirectConnection,
                                      Q_RETURN_ARG(bool, isRunningRet), Q_ARG(QString, appId));
        if (!ok) {
            qWarning() << "[AppLaunchService] Failed to invoke isAppRunning(QString)";
        } else {
            isRunning = isRunningRet;
        }
    }

    if (isRunning) {
        if (m_appLifecycleManager) {
            const bool ok = QMetaObject::invokeMethod(m_appLifecycleManager, "bringToForeground",
                                                      Qt::DirectConnection, Q_ARG(QString, appId));
            if (!ok)
                qWarning() << "[AppLaunchService] Failed to invoke bringToForeground(QString)";
        }

        invokeVoid(appWindowRef, "show", {appId, name, icon, type, QVariant(), -1});

        if (m_uiStore)
            invokeVoid(m_uiStore, "restoreApp", {appId, name, icon});

        m_launchingApps.remove(appId);
        emit appLaunchCompleted(appId, name);
        return true;
    }

    if (m_uiStore)
        invokeVoid(m_uiStore, "openApp", {appId, name, icon});

    emit appLaunchProgress(appId, 30);
    invokeVoid(appWindowRef, "show", {appId, name, icon, type, QVariant(), -1});
    emit appLaunchProgress(appId, 60);

    if (m_appLifecycleManager) {
        const bool ok = QMetaObject::invokeMethod(m_appLifecycleManager, "bringToForeground",
                                                  Qt::DirectConnection, Q_ARG(QString, appId));
        if (!ok)
            qWarning() << "[AppLaunchService] Failed to invoke bringToForeground(QString)";
    }

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
