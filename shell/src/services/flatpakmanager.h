#ifndef FLATPAKMANAGER_H
#define FLATPAKMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class FlatpakManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)

  public:
    explicit FlatpakManager(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }

    // Reads `flatpak list --app`. Each entry: {ref, branch, arch, installation}.
    Q_INVOKABLE QVariantList installedApps();

    // `flatpak info --show-permissions <ref>` parsed into nested map.
    // Top-level keys mirror section names (e.g. "Context", "Session Bus Policy").
    // Values for "Context" are themselves dicts (shared/sockets/devices/...).
    // Values for the bus-policy sections map name -> "talk"|"own"|"none".
    Q_INVOKABLE QVariantMap permissions(const QString &ref);

    // Just the user override file at ~/.local/share/flatpak/overrides/<ref>.
    // Same shape as permissions() but only contains keys the user has changed.
    Q_INVOKABLE QVariantMap userOverrides(const QString &ref);

    // `policy` is one of "allow" (talk), "own", or "none" (revoke).
    // Empty policy resets the entry, letting the app's manifest default apply.
    Q_INVOKABLE bool setTalkPolicy(const QString &ref, const QString &busName,
                                   const QString &policy);

    // `mode` is "rw", "ro", "create", or empty to remove a previously granted
    // filesystem path. Path can be xdg-* token or absolute path.
    Q_INVOKABLE bool setFilesystemPolicy(const QString &ref, const QString &path,
                                         const QString &mode);

    // Removes all user overrides for the app.
    Q_INVOKABLE bool resetOverrides(const QString &ref);

    // Invalidates the cached installedApps list so the next call re-shells.
    Q_INVOKABLE void refresh();

  signals:
    void installedAppsChanged();
    void overridesChanged(const QString &ref);

  private:
    bool         runFlatpak(const QStringList &args, QByteArray *stdOut = nullptr) const;
    QVariantMap  parsePermissionsIni(const QString &iniText) const;

    QVariantList m_installedCache;
    bool         m_installedCached = false;
    bool         m_available;
};

#endif
