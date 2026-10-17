#ifndef NOTIFICATIONTARGET_H
#define NOTIFICATIONTARGET_H

#include <QString>
#include <QStringList>

class MarathonAppRegistry;

// Which installed app a notification belongs to.
namespace NotificationTarget {

    // The app a process runs as, from its /proc/<pid>/cgroup line: Marathon's
    // marathon-app-<id>, Flatpak's app-flatpak-<id>-<n>.scope, or the XDG
    // app-[<launcher>-]<id>[@<instance>|-<random>] unit names.
    QString appFromCgroup(const QString &cgroup);

    // The registry id of the first candidate that names an installed app, by
    // id (a .desktop suffix is dropped) or by display name, ignoring case.
    QString resolve(const QStringList &candidates, const MarathonAppRegistry *registry);

    // appFromCgroup() for a running process.
    QString appForPid(uint pid);

} // namespace NotificationTarget

#endif // NOTIFICATIONTARGET_H
