#include "sailjail.h"

namespace Sailjail {

QStringList bwrapArgs(const QStringList &permissions, const QString &organization,
                      const QString &application, const QString &home, const QString &runtimeDir) {
    QStringList a;
    a << QStringLiteral("--die-with-parent") << QStringLiteral("--new-session")
      << QStringLiteral("--unshare-pid") << QStringLiteral("--unshare-ipc");
    if (!permissions.contains(QStringLiteral("Internet")))
        a << QStringLiteral("--unshare-net");

    for (const char *dir : {"/etc", "/lib", "/bin", "/sbin"})
        a << QStringLiteral("--ro-bind-try") << QLatin1String(dir) << QLatin1String(dir);
    a << QStringLiteral("--ro-bind") << QStringLiteral("/usr") << QStringLiteral("/usr");
    a << QStringLiteral("--proc") << QStringLiteral("/proc") << QStringLiteral("--dev")
      << QStringLiteral("/dev") << QStringLiteral("--dev-bind-try") << QStringLiteral("/dev/dri")
      << QStringLiteral("/dev/dri") << QStringLiteral("--ro-bind-try") << QStringLiteral("/sys")
      << QStringLiteral("/sys") << QStringLiteral("--ro-bind-try") << QStringLiteral("/run/dbus")
      << QStringLiteral("/run/dbus") << QStringLiteral("--tmpfs") << QStringLiteral("/tmp");

    // Home is private; the app writes only its own directories, as Sailjail allows.
    a << QStringLiteral("--tmpfs") << home;
    const QString sub = QLatin1Char('/') + organization + QLatin1Char('/') + application;
    for (const char *base : {"/.local/share", "/.cache", "/.config"})
        a << QStringLiteral("--bind") << home + QLatin1String(base) + sub << home + QLatin1String(base) + sub;
    a << QStringLiteral("--ro-bind-try") << home + QStringLiteral("/.config/dconf")
      << home + QStringLiteral("/.config/dconf");
    a << QStringLiteral("--bind") << runtimeDir << runtimeDir;

    static const struct {
        const char *permission;
        const char *folder;
    } kFolders[] = {{"Pictures", "Pictures"},   {"Music", "Music"},         {"Videos", "Videos"},
                    {"Documents", "Documents"}, {"Downloads", "Downloads"}, {"Audio", "Music"}};
    for (const auto &f : kFolders) {
        if (permissions.contains(QLatin1String(f.permission))) {
            const QString path = home + QLatin1Char('/') + QLatin1String(f.folder);
            a << QStringLiteral("--bind-try") << path << path;
        }
    }
    if (permissions.contains(QStringLiteral("Camera"))) {
        for (int i = 0; i < 4; ++i) {
            const QString dev = QStringLiteral("/dev/video%1").arg(i);
            a << QStringLiteral("--dev-bind-try") << dev << dev;
        }
    }
    if (permissions.contains(QStringLiteral("RemovableMedia")))
        a << QStringLiteral("--bind-try") << QStringLiteral("/run/media") << QStringLiteral("/run/media");
    return a;
}

} // namespace Sailjail
