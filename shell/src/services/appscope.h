#pragma once

#include <QByteArray>
#include <QString>

// The systemd scope a native app runs in, freezable on its own without
// touching the shell: flatpak's app-flatpak-<id>-<instance>.scope, or the
// app-<launcher>-<id>-<random>.scope a desktop launcher made
// (systemd.io/DESKTOP_ENVIRONMENTS).
namespace AppScope {

    // Unit name for a cgroup path from /proc/<pid>/cgroup ("0::/user.slice/..."
    // with the prefix removed), or empty. A process the shell started itself
    // shares the shell's cgroup, and on a dev host that can be a terminal's
    // app-*.scope, so the shell's own cgroup and its ancestors never count.
    inline QString unitForCgroup(const QString &cgroup, const QString &shellCgroup) {
        if (cgroup.isEmpty() || cgroup == shellCgroup ||
            shellCgroup.startsWith(cgroup + QLatin1Char('/')))
            return {};
        const QString unit = cgroup.section(QLatin1Char('/'), -1);
        if (!unit.startsWith(QLatin1String("app-")) || !unit.endsWith(QLatin1String(".scope")))
            return {};
        return unit;
    }

    // The unified-hierarchy path in a /proc/<pid>/cgroup file.
    inline QString cgroupFromProcFile(const QByteArray &contents) {
        for (const QByteArray &line : contents.split('\n')) {
            if (line.startsWith("0::"))
                return QString::fromUtf8(line.mid(3)).trimmed();
        }
        return {};
    }

} // namespace AppScope
