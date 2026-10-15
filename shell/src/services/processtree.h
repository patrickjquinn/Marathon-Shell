#pragma once

#include <QFile>

// Whether ancestorPid is childPid or one of its ancestors, from /proc.
inline bool isDescendantPid(qint64 childPid, qint64 ancestorPid) {
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
