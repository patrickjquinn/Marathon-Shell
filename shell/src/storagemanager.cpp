#include "storagemanager.h"
#include <QDebug>
#include <QDir>

StorageManager::StorageManager(QObject *parent)
    : QObject(parent)
    , m_storageInfo(QStorageInfo::root())
    , m_totalSpace(0)
    , m_availableSpace(0)
    , m_usedSpace(0)
    , m_usedPercentage(0.0) {
    // Initial update
    updateStorageInfo();

    // Auto-refresh every 30 seconds
    m_refreshTimer = new QTimer(this);
    connect(m_refreshTimer, &QTimer::timeout, this, &StorageManager::updateStorageInfo);
    m_refreshTimer->start(30000); // 30 seconds

    qDebug() << "[StorageManager] Initialized for:" << m_storageInfo.rootPath();
    qDebug() << "[StorageManager] Total:" << formatBytes(m_totalSpace)
             << "Used:" << formatBytes(m_usedSpace)
             << "Available:" << formatBytes(m_availableSpace);
}

void StorageManager::updateStorageInfo() {
    m_storageInfo.refresh();

    if (!m_storageInfo.isValid() || !m_storageInfo.isReady()) {
        qWarning() << "[StorageManager] Storage info not valid or ready";
        return;
    }

    m_totalSpace     = m_storageInfo.bytesTotal();
    m_availableSpace = m_storageInfo.bytesAvailable();
    m_usedSpace      = m_totalSpace - m_availableSpace;

    if (m_totalSpace > 0) {
        m_usedPercentage = (static_cast<double>(m_usedSpace) / static_cast<double>(m_totalSpace));
    } else {
        m_usedPercentage = 0.0;
    }

    emit storageChanged();
}

void StorageManager::refresh() {
    qDebug() << "[StorageManager] Manual refresh requested";
    updateStorageInfo();
}

QString StorageManager::totalSpaceString() const {
    return formatBytes(m_totalSpace);
}

QString StorageManager::availableSpaceString() const {
    return formatBytes(m_availableSpace);
}

QString StorageManager::usedSpaceString() const {
    return formatBytes(m_usedSpace);
}

QString StorageManager::formatBytes(qint64 bytes) const {
    const qint64 KB = 1024;
    const qint64 MB = KB * 1024;
    const qint64 GB = MB * 1024;
    const qint64 TB = GB * 1024;

    if (bytes >= TB) {
        return QString::number(bytes / static_cast<double>(TB), 'f', 1) + " TB";
    } else if (bytes >= GB) {
        return QString::number(bytes / static_cast<double>(GB), 'f', 1) + " GB";
    } else if (bytes >= MB) {
        return QString::number(bytes / static_cast<double>(MB), 'f', 1) + " MB";
    } else if (bytes >= KB) {
        return QString::number(bytes / static_cast<double>(KB), 'f', 1) + " KB";
    } else {
        return QString::number(bytes) + " bytes";
    }
}
