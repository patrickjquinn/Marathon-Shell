#ifndef FLATPAKMANAGER_H
#define FLATPAKMANAGER_H

#include <QHash>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class FlatpakManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY installedAppsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

  public:
    explicit FlatpakManager(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    QVariantList installedApps() const {
        return m_installed;
    }
    bool loading() const {
        return m_pendingOps > 0;
    }

    // Kicks off `flatpak list --app`; emits installedAppsChanged on success.
    Q_INVOKABLE void refresh();

    // Async fetch of effective permissions (flatpak info --show-permissions).
    // Result delivered via permissionsReady(ref, perms). Cached -- second call
    // for the same ref reuses the cache; call refresh() then requestPermissions()
    // to force a re-read.
    Q_INVOKABLE void requestPermissions(const QString &ref);

    // Reads the user override file under ~/.local/share/flatpak/overrides/<ref>.
    // Result delivered via userOverridesReady(ref, overrides). Fast (small file)
    // but async-shaped for API consistency.
    Q_INVOKABLE void requestUserOverrides(const QString &ref);

    // `policy`: "allow" / "talk" -> --talk-name, "own" -> --own-name,
    // "" or "none" -> --no-talk-name (revoke). Result via overrideApplied.
    Q_INVOKABLE void setTalkPolicy(const QString &ref, const QString &busName,
                                   const QString &policy);

    // `mode`: "rw" / "ro" / "create" -> --filesystem=path[:mode];
    // "" -> --nofilesystem=path (revoke). Path can be xdg-* token or absolute.
    Q_INVOKABLE void setFilesystemPolicy(const QString &ref, const QString &path,
                                         const QString &mode);

    // `flatpak override --user --reset <ref>` then emit overrideApplied.
    Q_INVOKABLE void resetOverrides(const QString &ref);

    // Whatever permissions() has fetched for this ref so far; empty if never.
    Q_INVOKABLE QVariantMap cachedPermissions(const QString &ref) const;

  signals:
    void installedAppsChanged();
    void loadingChanged();
    void permissionsReady(const QString &ref, const QVariantMap &perms);
    void userOverridesReady(const QString &ref, const QVariantMap &overrides);
    void overrideApplied(const QString &ref, bool success);

  private:
    void                        startProcess(const QStringList                                   &args,
                                             const std::function<void(bool, const QByteArray &)> &done);
    QVariantMap                 parsePermissionsIni(const QString &iniText) const;
    void                        beginOp();
    void                        endOp();
    void                        parseInstalled(const QByteArray &out);

    QVariantList                m_installed;
    QHash<QString, QVariantMap> m_permCache;
    int                         m_pendingOps = 0;
    bool                        m_available;
};

#endif
