#pragma once

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>

// Session services a package installed, admitted over D-Bus by their systemd
// user unit and executable: <dir>/<unit>.json holds
// {"exec": "/usr/bin/pilotd", "permissions": ["contacts", ...]}.
// The caller id is "service:<unit>", never a Marathon app id.
namespace ServiceCaller {

    inline const QString kDir    = QStringLiteral("/usr/share/marathon-shell/services");
    inline const QString kPrefix = QStringLiteral("service:");

    // The unit of a /proc/<pid>/cgroup (cgroup v2), if a user service.
    inline QString unitOf(const QByteArray &cgroup) {
        static const QRegularExpression unit(QStringLiteral("^[A-Za-z0-9@._-]+\\.service$"));
        const QList<QByteArray> lines = cgroup.split('\n');
        for (const QByteArray &line : lines) {
            if (!line.startsWith("0::/"))
                continue;
            const QString last = QString::fromUtf8(line.mid(3)).section(QLatin1Char('/'), -1);
            return unit.match(last).hasMatch() ? last : QString();
        }
        return {};
    }

    inline QJsonObject declaration(const QString &unit, const QString &dir) {
        QFile f(dir + QLatin1Char('/') + unit + QStringLiteral(".json"));
        if (unit.isEmpty() || !f.open(QIODevice::ReadOnly))
            return {};
        return QJsonDocument::fromJson(f.readAll()).object();
    }

    // "service:<unit>" when pid runs a declared service's executable in its
    // own unit; empty otherwise.
    inline QString resolve(qint64 pid, const QString &dir = kDir,
                           const QString &proc = QStringLiteral("/proc")) {
        QFile cgroup(QStringLiteral("%1/%2/cgroup").arg(proc).arg(pid));
        if (!cgroup.open(QIODevice::ReadOnly))
            return {};
        const QString     unit = unitOf(cgroup.readAll());
        const QJsonObject decl = declaration(unit, dir);
        const QString     exec =
            QFileInfo(decl.value(QStringLiteral("exec")).toString()).canonicalFilePath();
        const QString running =
            QFileInfo(QStringLiteral("%1/%2/exe").arg(proc).arg(pid)).canonicalFilePath();
        if (exec.isEmpty() || running != exec)
            return {};
        return kPrefix + unit;
    }

    inline bool allowed(const QString &caller, const QStringList &permissions,
                        const QString &dir = kDir) {
        if (!caller.startsWith(kPrefix))
            return false;
        const QJsonArray declared = declaration(caller.mid(kPrefix.size()), dir)
                                        .value(QStringLiteral("permissions"))
                                        .toArray();
        for (const QString &p : permissions) {
            if (declared.contains(p))
                return true;
        }
        return false;
    }

} // namespace ServiceCaller
