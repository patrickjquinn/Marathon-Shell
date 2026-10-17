#pragma once

#include <QDir>
#include <QString>

// Where Marathon apps live. An app's code and the record of what the user
// approved are never inside a directory the app can write: user installs sit
// under userInstalls() (bound read-only into the sandbox), the app's own data
// under dataDir() (bound read-write), as Flatpak keeps /app apart from
// ~/.var/app/<id>.
namespace MarathonAppPaths {

    // Marathon's own apps, installed read-only by the OS. MARATHON_APPS_DIR
    // points a development shell at a build's install tree instead.
    inline QString systemApps() {
        return qEnvironmentVariable("MARATHON_APPS_DIR",
                                    QStringLiteral("/usr/share/marathon-apps"));
    }

    inline QString xdgDir(const char *variable, const QString &fallback) {
        return qEnvironmentVariable(variable, QDir::homePath() + fallback);
    }

    // <id>/files is the package as installed, <id>/receipt.json what the
    // installer recorded about it.
    inline QString userInstalls() {
        return xdgDir("XDG_DATA_HOME", QStringLiteral("/.local/share")) +
            QStringLiteral("/marathon/apps");
    }
    inline QString installDir(const QString &appId) {
        return userInstalls() + QLatin1Char('/') + appId;
    }
    inline QString filesDir(const QString &appId) {
        return installDir(appId) + QStringLiteral("/files");
    }
    inline QString receiptPath(const QString &appId) {
        return installDir(appId) + QStringLiteral("/receipt.json");
    }

    // Before installs moved out, <dataDir> was also the install directory.
    inline QString legacyInstalls() {
        return xdgDir("XDG_DATA_HOME", QStringLiteral("/.local/share")) +
            QStringLiteral("/marathon-apps");
    }
    inline QString dataDir(const QString &appId) {
        return legacyInstalls() + QLatin1Char('/') + appId;
    }
    inline QString configDir(const QString &appId) {
        return xdgDir("XDG_CONFIG_HOME", QStringLiteral("/.config")) +
            QStringLiteral("/marathon-apps/") + appId;
    }
    inline QString cacheDir(const QString &appId) {
        return xdgDir("XDG_CACHE_HOME", QStringLiteral("/.cache")) +
            QStringLiteral("/marathon-apps/") + appId;
    }

} // namespace MarathonAppPaths
