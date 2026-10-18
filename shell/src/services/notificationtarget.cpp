#include "notificationtarget.h"

#include "marathonappregistry.h"

#include <QFile>
#include <QRegularExpression>

namespace {

    QString unitBaseName(const QString &cgroup) {
        QString name = cgroup.section(QLatin1Char('/'), -1);
        for (const auto suffix : {QLatin1String(".scope"), QLatin1String(".service")}) {
            if (name.endsWith(suffix))
                name.chop(suffix.size());
        }
        return name.replace(QLatin1String("\\x2d"), QLatin1String("-"));
    }

    // systemd.unit(5) "Desktop Environment Integration": app[-<launcher>]-<id>
    // followed by @<instance> (services) or -<random> (scopes).
    QString xdgAppId(QString rest, bool isScope) {
        if (isScope) {
            const qsizetype dash = rest.lastIndexOf(QLatin1Char('-'));
            if (dash <= 0)
                return {};
            rest.truncate(dash);
        } else {
            rest = rest.section(QLatin1Char('@'), 0, 0);
        }
        // A launcher name never contains a dot; an application id does.
        const qsizetype dash = rest.indexOf(QLatin1Char('-'));
        if (dash > 0 && !rest.left(dash).contains(QLatin1Char('.')) &&
            rest.mid(dash + 1).contains(QLatin1Char('.')))
            rest = rest.mid(dash + 1);
        return rest;
    }

} // namespace

QString NotificationTarget::appFromCgroup(const QString &cgroup) {
    const bool    isScope = cgroup.endsWith(QLatin1String(".scope"));
    const QString name    = unitBaseName(cgroup);
    if (name.startsWith(QLatin1String("marathon-app-")))
        return name.mid(int(qstrlen("marathon-app-")));
    if (name.startsWith(QLatin1String("app-flatpak-"))) {
        static const QRegularExpression kInstance(QStringLiteral("-\\d+$"));
        return name.mid(int(qstrlen("app-flatpak-"))).remove(kInstance);
    }
    if (name.startsWith(QLatin1String("app-")))
        return xdgAppId(name.mid(4), isScope);
    return {};
}

QString NotificationTarget::resolve(const QStringList         &candidates,
                                    const MarathonAppRegistry *registry) {
    if (!registry)
        return {};
    const QStringList ids = registry->getAllAppIds();
    for (QString candidate : candidates) {
        candidate = candidate.trimmed();
        if (candidate.endsWith(QLatin1String(".desktop")))
            candidate.chop(int(qstrlen(".desktop")));
        if (candidate.isEmpty())
            continue;
        if (registry->hasApp(candidate))
            return candidate;
        for (const QString &id : ids) {
            if (id.compare(candidate, Qt::CaseInsensitive) == 0 ||
                registry->getApp(id)
                        .value(QStringLiteral("name"))
                        .toString()
                        .compare(candidate, Qt::CaseInsensitive) == 0)
                return id;
        }
    }
    return {};
}

QString NotificationTarget::appForPid(uint pid) {
    QFile file(QStringLiteral("/proc/%1/cgroup").arg(pid));
    if (pid == 0 || !file.open(QIODevice::ReadOnly))
        return {};
    // cgroup v2's unified hierarchy is the "0::" line.
    const QList<QByteArray> lines = file.readAll().split('\n');
    for (const QByteArray &line : lines) {
        if (line.startsWith("0::"))
            return appFromCgroup(QString::fromUtf8(line));
    }
    return {};
}
