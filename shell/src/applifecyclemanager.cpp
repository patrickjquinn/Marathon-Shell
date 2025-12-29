#include "applifecyclemanager.h"

#include "applaunchservice.h"
#include "taskmodel.h"

#include <QDateTime>
#include <QMetaObject>
#include <QVariant>

AppLifecycleManager::AppLifecycleManager(TaskModel *taskModel, AppLaunchService *appLaunchService,
                                         QObject *parent)
    : QObject(parent)
    , m_taskModel(taskModel)
    , m_appLaunchService(appLaunchService) {}

void AppLifecycleManager::registerApp(const QString &appId, QObject *appInstance) {
    if (appId.isEmpty() || !appInstance)
        return;

    m_appRegistry.insert(appId, appInstance);
    emit appRegistered(appId, appInstance);

    if (!m_appStates.contains(appId)) {
        AppState st;
        st.launchTimeMs = QDateTime::currentMSecsSinceEpoch();
        m_appStates.insert(appId, st);
    }

    // If this app was queued to be foregrounded, do it now.
    if (m_pendingForegroundApps.contains(appId)) {
        m_pendingForegroundApps.removeAll(appId);
        bringToForeground(appId);
    }

    ensureTaskExists(appId);
}

void AppLifecycleManager::unregisterApp(const QString &appId) {
    if (appId.isEmpty())
        return;

    // Clean up task when app unregistered
    if (m_taskModel) {
        if (Task *task = m_taskModel->getTaskByAppId(appId)) {
            m_taskModel->closeTask(task->id());
        }
    }

    m_appRegistry.remove(appId);
    m_appStates.remove(appId);
    m_pendingForegroundApps.removeAll(appId);
    if (m_foregroundAppId == appId)
        m_foregroundAppId.clear();

    emit appUnregistered(appId);
}

QObject *AppLifecycleManager::getAppInstance(const QString &appId) const {
    return m_appRegistry.value(appId, nullptr);
}

QVariantMap AppLifecycleManager::appInfoFromInstance(const QString &appId,
                                                     QObject       *instance) const {
    QVariantMap info;
    info["appId"]          = appId;
    info["appName"]        = instance ? instance->property("appName") : QVariant();
    info["appIcon"]        = instance ? instance->property("appIcon") : QVariant();
    info["appType"]        = instance ? instance->property("appType") : QVariant();
    info["isNative"]       = instance ? instance->property("isNative") : QVariant();
    info["surfaceId"]      = instance ? instance->property("surfaceId") : QVariant();
    info["waylandSurface"] = instance ? instance->property("waylandSurface") : QVariant();
    return info;
}

void AppLifecycleManager::bringToForeground(const QString &appId) {
    if (appId.isEmpty())
        return;

    // Pause current foreground app
    if (!m_foregroundAppId.isEmpty() && m_foregroundAppId != appId) {
        if (QObject *prev = m_appRegistry.value(m_foregroundAppId)) {
            invokeVoid(prev, "pause");
            invokeVoid(prev, "stop");
        }
        if (m_appStates.contains(m_foregroundAppId)) {
            auto &st    = m_appStates[m_foregroundAppId];
            st.isActive = false;
            st.isPaused = true;
        }
    }

    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "start");
        invokeVoid(app, "resume");

        m_foregroundAppId = appId;
        if (m_appStates.contains(appId)) {
            auto &st        = m_appStates[appId];
            st.isActive     = true;
            st.isPaused     = false;
            st.isMinimized  = false;
            st.lastActiveMs = QDateTime::currentMSecsSinceEpoch();
        }
        ensureTaskExists(appId);
    } else {
        // Defer foreground until registration arrives
        if (!m_pendingForegroundApps.contains(appId))
            m_pendingForegroundApps.push_back(appId);
    }
}

void AppLifecycleManager::restoreApp(const QString &appId) {
    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "restore");
        bringToForeground(appId);
    }
}

bool AppLifecycleManager::handleSystemBack() {
    if (m_foregroundAppId.isEmpty())
        return false;

    QObject *app = m_appRegistry.value(m_foregroundAppId);
    if (!app)
        return false;

    const bool isNative = app->property("isNative").toBool();
    if (isNative) {
        // Marathon apps run out-of-process but are still rendered as Wayland clients (NativeAppWindow).
        // For those, Escape injection is not the right "Back" semantic; instead send a lifecycle
        // back event to the runner so it can call MApp.handleBack().
        if (m_appLaunchService && m_appLaunchService->isMarathonAppId(m_foregroundAppId)) {
            return m_appLaunchService->sendBackToRunner(m_foregroundAppId);
        }
        QObject *compositor = m_appLaunchService ? m_appLaunchService->compositor() : nullptr;
        if (compositor) {
            // Escape key
            if (invokeInjectKey(compositor, /*Qt.Key_Escape*/ 0x01000000, /*mods*/ 0, true) &&
                invokeInjectKey(compositor, /*Qt.Key_Escape*/ 0x01000000, /*mods*/ 0, false)) {
                return true;
            }
        }
        return false;
    }

    bool handled = false;
    invokeBool(app, "handleBack", &handled);
    return handled;
}

bool AppLifecycleManager::handleSystemForward() {
    if (m_foregroundAppId.isEmpty())
        return false;

    QObject *app = m_appRegistry.value(m_foregroundAppId);
    if (!app)
        return false;

    const bool isNative = app->property("isNative").toBool();
    if (isNative) {
        if (m_appLaunchService && m_appLaunchService->isMarathonAppId(m_foregroundAppId)) {
            return m_appLaunchService->sendForwardToRunner(m_foregroundAppId);
        }
        QObject *compositor = m_appLaunchService ? m_appLaunchService->compositor() : nullptr;
        if (compositor) {
            // Alt+Right
            if (invokeInjectKey(compositor, /*Qt.Key_Right*/ 0x01000014,
                                /*Qt.AltModifier*/ 0x08000000, true) &&
                invokeInjectKey(compositor, /*Qt.Key_Right*/ 0x01000014,
                                /*Qt.AltModifier*/ 0x08000000, false)) {
                return true;
            }
        }
        return false;
    }

    bool handled = false;
    invokeBool(app, "handleForward", &handled);
    return handled;
}

bool AppLifecycleManager::minimizeForegroundApp() {
    if (m_foregroundAppId.isEmpty())
        return false;

    const QString appId = m_foregroundAppId;
    ensureTaskExists(appId);

    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "minimize");
        invokeVoid(app, "stop");
    }

    if (m_appStates.contains(appId)) {
        auto &st       = m_appStates[appId];
        st.isMinimized = true;
        st.isActive    = false;
    }

    m_foregroundAppId.clear();
    return true;
}

void AppLifecycleManager::broadcastLowMemory() {
    for (auto it = m_appRegistry.constBegin(); it != m_appRegistry.constEnd(); ++it) {
        if (it.value())
            invokeVoid(it.value(), "handleLowMemory");
    }
}

void AppLifecycleManager::closeApp(const QString &appId, bool skipNativeClose) {
    if (appId.isEmpty())
        return;

    // Remove from TaskModel
    if (m_taskModel) {
        if (Task *task = m_taskModel->getTaskByAppId(appId)) {
            m_taskModel->closeTask(task->id());
        }
    }

    QObject *app = m_appRegistry.value(appId);
    if (app) {
        const int surfaceId = app->property("surfaceId").toInt();
        if (!skipNativeClose && surfaceId > 0 && m_appLaunchService) {
            m_appLaunchService->closeNativeApp(surfaceId);
        }
        invokeVoid(app, "close");
    }

    if (m_foregroundAppId == appId)
        m_foregroundAppId.clear();

    unregisterApp(appId);
}

QVariantMap AppLifecycleManager::getAppState(const QString &appId) const {
    if (!m_appStates.contains(appId))
        return {};
    const auto &st = m_appStates[appId];
    return {
        {"appId", appId},
        {"isActive", st.isActive},
        {"isPaused", st.isPaused},
        {"isMinimized", st.isMinimized},
        {"launchTime", st.launchTimeMs},
        {"lastActiveTime", st.lastActiveMs},
    };
}

bool AppLifecycleManager::isAppRunning(const QString &appId) const {
    return m_appRegistry.contains(appId);
}

QString AppLifecycleManager::getForegroundAppId() const {
    return m_foregroundAppId.isEmpty() ? QString() : m_foregroundAppId;
}

bool AppLifecycleManager::ensureTaskExists(const QString &appId) {
    if (!m_taskModel)
        return false;
    if (Task *task = m_taskModel->getTaskByAppId(appId))
        return task != nullptr;

    QObject *instance = m_appRegistry.value(appId);
    if (!instance)
        return false;

    const QString name = instance->property("appName").toString().isEmpty() ?
        appId :
        instance->property("appName").toString();
    const QString icon = instance->property("appIcon").toString();
    const QString type = instance->property("appType").toString().isEmpty() ?
        QStringLiteral("marathon") :
        instance->property("appType").toString();
    const int     surfaceId =
        instance->property("surfaceId").isValid() ? instance->property("surfaceId").toInt() : -1;
    QObject *surface = instance->property("waylandSurface").value<QObject *>();

    m_taskModel->launchTask(appId, name, icon, type, surfaceId, surface);
    return true;
}

bool AppLifecycleManager::invokeVoid(QObject *obj, const char *method) {
    if (!obj)
        return false;
    return QMetaObject::invokeMethod(obj, method, Qt::DirectConnection);
}

bool AppLifecycleManager::invokeBool(QObject *obj, const char *method, bool *out) {
    if (!obj)
        return false;
    QVariant   ret;
    auto       r  = Q_RETURN_ARG(QVariant, ret);
    const bool ok = QMetaObject::invokeMethod(obj, method, Qt::DirectConnection, r);
    if (ok && out)
        *out = ret.toBool();
    return ok;
}

bool AppLifecycleManager::invokeInjectKey(QObject *compositor, int key, int modifiers,
                                          bool pressed) {
    if (!compositor)
        return false;
    return QMetaObject::invokeMethod(compositor, "injectKey", Qt::DirectConnection, Q_ARG(int, key),
                                     Q_ARG(int, modifiers), Q_ARG(bool, pressed));
}
