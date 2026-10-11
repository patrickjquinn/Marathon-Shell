// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keelcallertrust.h"

#include <QCoreApplication>
#include <QFile>

#include <grp.h>
#include <sys/stat.h>

namespace KeelCallerTrust {

QStringList trustedExecutables()
{
    return {QStringLiteral("/usr/bin/pilotd"), QStringLiteral("/usr/bin/keel-mcp")};
}

bool runsOneOf(qint64 pid, const QStringList &paths)
{
    if (pid <= 0)
        return false;
    struct stat exe {};
    const QByteArray link = "/proc/" + QByteArray::number(pid) + "/exe";
    if (::stat(link.constData(), &exe) != 0)
        return false;
    for (const QString &path : paths) {
        struct stat candidate {};
        if (::stat(QFile::encodeName(path).constData(), &candidate) == 0 && candidate.st_dev == exe.st_dev
            && candidate.st_ino == exe.st_ino)
            return true;
    }
    return false;
}

std::optional<uint> gidField(qint64 pid, int field)
{
    if (pid <= 0)
        return std::nullopt;
    QFile status(QStringLiteral("/proc/%1/status").arg(pid));
    if (!status.open(QIODevice::ReadOnly))
        return std::nullopt;
    // "Gid:\t<real>\t<effective>\t<saved>\t<filesystem>"
    for (const QByteArray &line : status.readAll().split('\n')) {
        if (!line.startsWith("Gid:"))
            continue;
        const QList<QByteArray> ids = line.mid(4).simplified().split(' ');
        bool ok = false;
        const uint gid = ids.value(field).toUInt(&ok);
        return ok ? std::optional<uint>(gid) : std::nullopt;
    }
    return std::nullopt;
}

std::optional<uint> effectiveGid(qint64 pid)
{
    return gidField(pid, 1);
}

// What a setgid program keeps after setting its effective group back:
// pilotd runs as the person's group and raises privileged only to read the
// calendar and contacts.
std::optional<uint> savedGid(qint64 pid)
{
    return gidField(pid, 2);
}

std::optional<uint> privilegedGid()
{
    const struct group *group = ::getgrnam("privileged");
    return group ? std::optional<uint>(group->gr_gid) : std::nullopt;
}

bool isTrusted(qint64 pid)
{
    if (pid <= 0)
        return false;
    if (pid == QCoreApplication::applicationPid())
        return true;
    if (runsOneOf(pid, trustedExecutables()))
        return true;
    const std::optional<uint> privileged = privilegedGid();
    return privileged && (effectiveGid(pid) == privileged || savedGid(pid) == privileged);
}

} // namespace KeelCallerTrust
