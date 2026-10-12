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

  signals:
    void installedAppsChanged();
    void loadingChanged();
    void permissionsReady(const QString &ref, const QVariantMap &perms);

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
