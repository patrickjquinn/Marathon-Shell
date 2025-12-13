#include "StorageInfo.h"

StorageInfo::StorageInfo(QObject *parent)
    : QObject(parent)
    , m_storage(QStorageInfo::root()) {
    refresh();
}

void StorageInfo::refresh() {
    m_storage.refresh();
    emit changed();
}

qint64 StorageInfo::totalSpace() const {
    return m_storage.bytesTotal();
}

qint64 StorageInfo::availableSpace() const {
    return m_storage.bytesAvailable();
}

qint64 StorageInfo::usedSpace() const {
    return totalSpace() - availableSpace();
}

double StorageInfo::usedPercentage() const {
    const qint64 total = totalSpace();
    if (total <= 0)
        return 0.0;
    return static_cast<double>(usedSpace()) / static_cast<double>(total);
}

QString StorageInfo::totalSpaceString() const {
    return formatBytes(totalSpace());
}

QString StorageInfo::availableSpaceString() const {
    return formatBytes(availableSpace());
}

QString StorageInfo::usedSpaceString() const {
    return formatBytes(usedSpace());
}

QString StorageInfo::formatBytes(qint64 bytes) {
    constexpr qint64 KB = 1024;
    constexpr qint64 MB = KB * 1024;
    constexpr qint64 GB = MB * 1024;
    constexpr qint64 TB = GB * 1024;

    if (bytes >= TB)
        return QString::number(bytes / double(TB), 'f', 1) + " TB";
    if (bytes >= GB)
        return QString::number(bytes / double(GB), 'f', 1) + " GB";
    if (bytes >= MB)
        return QString::number(bytes / double(MB), 'f', 1) + " MB";
    if (bytes >= KB)
        return QString::number(bytes / double(KB), 'f', 1) + " KB";
    return QString::number(bytes) + " bytes";
}
