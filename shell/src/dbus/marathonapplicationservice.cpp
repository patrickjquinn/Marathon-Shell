#include "marathonapplicationservice.h"
#include "../marathonappregistry.h"
#include "../marathonapploader.h"
#include "../taskmodel.h"
#include <QDBusConnection>
#include <QDebug>

MarathonApplicationService::MarathonApplicationService(MarathonAppRegistry *registry,
                                                       MarathonAppLoader   *loader,
                                                       TaskModel *taskModel, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
    , m_loader(loader)
    , m_taskModel(taskModel) {
    connect(m_loader, &MarathonAppLoader::appLoaded, this,
            [this](const QString &appId) { emit AppLaunched(appId); });
}

MarathonApplicationService::~MarathonApplicationService() {}

bool MarathonApplicationService::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.marathon.ApplicationService")) {
        qWarning() << "[ApplicationService] Failed to register service:"
                   << bus.lastError().message();
        return false;
    }

    if (!bus.registerObject("/org/marathon/ApplicationService", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qWarning() << "[ApplicationService] Failed to register object:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[ApplicationService] ✓ Registered on D-Bus";
    return true;
}

QString MarathonApplicationService::LaunchApp(const QString &appId, const QVariantMap &params) {
    qInfo() << "[ApplicationService] LaunchApp:" << appId << "params:" << params;

    if (!m_registry->hasApp(appId)) {
        QString error = QString("App not found: %1").arg(appId);
        emit    Error(appId, error);
        return QString();
    }

    QObject *appInstance = m_loader->loadApp(appId);
    if (appInstance) {
        emit AppLaunched(appId);
        return appId;
    } else {
        emit Error(appId, "Failed to launch app");
        return QString();
    }
}

QVariantList MarathonApplicationService::ListApps(const QVariantMap &filter) {
    QVariantList result;
    int          count = m_registry->rowCount();

    for (int i = 0; i < count; ++i) {
        QModelIndex index = m_registry->index(i);
        QVariantMap appInfo;
        appInfo["id"]   = m_registry->data(index, MarathonAppRegistry::IdRole).toString();
        appInfo["name"] = m_registry->data(index, MarathonAppRegistry::NameRole).toString();
        appInfo["icon"] = m_registry->data(index, MarathonAppRegistry::IconRole).toString();
        result.append(appInfo);
    }

    return result;
}

QVariantMap MarathonApplicationService::GetAppInfo(const QString &appId) {
    QVariantMap info;

    if (!m_registry->hasApp(appId)) {
        return info;
    }

    int count = m_registry->rowCount();
    for (int i = 0; i < count; ++i) {
        QModelIndex index = m_registry->index(i);
        QString     id    = m_registry->data(index, MarathonAppRegistry::IdRole).toString();
        if (id == appId) {
            info["id"]   = id;
            info["name"] = m_registry->data(index, MarathonAppRegistry::NameRole).toString();
            info["icon"] = m_registry->data(index, MarathonAppRegistry::IconRole).toString();
            info["entryPoint"] =
                m_registry->data(index, MarathonAppRegistry::EntryPointRole).toString();
            break;
        }
    }

    return info;
}

bool MarathonApplicationService::CloseApp(const QString &appId) {
    qInfo() << "[ApplicationService] CloseApp:" << appId;

    m_loader->unloadApp(appId);
    emit AppClosed(appId);

    return true;
}

bool MarathonApplicationService::FocusApp(const QString &appId) {
    qInfo() << "[ApplicationService] FocusApp:" << appId;

    // TODO: Implement focus logic with window manager
    emit AppFocused(appId);
    return true;
}

QStringList MarathonApplicationService::RunningApps() {
    // Return list of loaded app IDs
    // TODO: Track loaded apps in MarathonAppLoader
    return QStringList();
}

bool MarathonApplicationService::PreloadApp(const QString &appId) {
    qInfo() << "[ApplicationService] PreloadApp:" << appId;

    // TODO: Implement preload logic (load QML component but don't show)
    return false;
}
