#include "marathonstorageservice.h"
#include "../storagemanager.h"
#include <QDBusConnection>
#include <QDebug>

MarathonStorageService::MarathonStorageService(StorageManager *storageManager, QObject *parent)
    : QObject(parent)
    , m_storageManager(storageManager) {
    // StorageManager updates via timer, no specific changed signals to connect
}

MarathonStorageService::~MarathonStorageService() {}

bool MarathonStorageService::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.marathon.StorageService")) {
        qWarning() << "[StorageService] Failed to register service:" << bus.lastError().message();
        return false;
    }

    if (!bus.registerObject("/org/marathon/StorageService", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals |
                                QDBusConnection::ExportAllProperties)) {
        qWarning() << "[StorageService] Failed to register object:" << bus.lastError().message();
        return false;
    }

    qInfo() << "[StorageService] ✓ Registered on D-Bus";
    return true;
}

qint64 MarathonStorageService::totalSpace() const {
    return m_storageManager ? m_storageManager->totalSpace() : 0;
}

qint64 MarathonStorageService::usedSpace() const {
    return m_storageManager ? m_storageManager->usedSpace() : 0;
}

qint64 MarathonStorageService::availableSpace() const {
    return m_storageManager ? m_storageManager->availableSpace() : 0;
}

double MarathonStorageService::usedPercentage() const {
    return m_storageManager ? m_storageManager->usedPercentage() : 0.0;
}

QVariantMap MarathonStorageService::GetStorageInfo() {
    QVariantMap info;
    info["totalSpace"]           = totalSpace();
    info["usedSpace"]            = usedSpace();
    info["availableSpace"]       = availableSpace();
    info["usedPercentage"]       = usedPercentage();
    info["totalSpaceString"]     = m_storageManager ? m_storageManager->totalSpaceString() : "";
    info["usedSpaceString"]      = m_storageManager ? m_storageManager->usedSpaceString() : "";
    info["availableSpaceString"] = m_storageManager ? m_storageManager->availableSpaceString() : "";
    return info;
}

QString MarathonStorageService::FormatSize(qint64 bytes) {
    // Implement size formatting directly
    const qint64 KB = 1024;
    const qint64 MB = KB * 1024;
    const qint64 GB = MB * 1024;
    const qint64 TB = GB * 1024;

    if (bytes >= TB) {
        return QString::number(bytes / static_cast<double>(TB), 'f', 2) + " TB";
    } else if (bytes >= GB) {
        return QString::number(bytes / static_cast<double>(GB), 'f', 2) + " GB";
    } else if (bytes >= MB) {
        return QString::number(bytes / static_cast<double>(MB), 'f', 2) + " MB";
    } else if (bytes >= KB) {
        return QString::number(bytes / static_cast<double>(KB), 'f', 2) + " KB";
    } else {
        return QString::number(bytes) + " B";
    }
}

bool MarathonStorageService::RequestStoragePermission(const QString &appId, const QString &path) {
    qInfo() << "[StorageService] RequestStoragePermission:" << appId << path;
    // TODO: Implement permission dialog
    return true;
}
