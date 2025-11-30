#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QMap>
#include <QVariantMap>

class MarathonPermissionManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool promptActive READ promptActive NOTIFY promptActiveChanged)
    Q_PROPERTY(QString currentAppId READ currentAppId NOTIFY currentRequestChanged)
    Q_PROPERTY(QString currentPermission READ currentPermission NOTIFY currentRequestChanged)

  public:
    enum PermissionStatus {
        NotRequested,
        Granted,
        Denied,
        Prompt // User needs to decide
    };
    Q_ENUM(PermissionStatus)

    explicit MarathonPermissionManager(QObject *parent = nullptr);

    // Check if an app has a specific permission
    Q_INVOKABLE bool hasPermission(const QString &appId, const QString &permission);

    // Request permission (shows prompt if not already granted/denied)
    Q_INVOKABLE void requestPermission(const QString &appId, const QString &permission);

    // Set permission (called by UI when user responds)
    Q_INVOKABLE void setPermission(const QString &appId, const QString &permission, bool granted,
                                   bool remember = true);

    // Get all permissions for an app
    Q_INVOKABLE QStringList getAppPermissions(const QString &appId);

    // Revoke a specific permission
    Q_INVOKABLE void revokePermission(const QString &appId, const QString &permission);

    // Get permission status
    Q_INVOKABLE PermissionStatus getPermissionStatus(const QString &appId,
                                                     const QString &permission);

    // Get list of all available permissions
    Q_INVOKABLE QStringList getAvailablePermissions();

    // Get human-readable permission description
    Q_INVOKABLE QString getPermissionDescription(const QString &permission);

    // Properties
    bool promptActive() const {
        return m_promptActive;
    }
    QString currentAppId() const {
        return m_currentAppId;
    }
    QString currentPermission() const {
        return m_currentPermission;
    }

  signals:
    void permissionGranted(const QString &appId, const QString &permission);
    void permissionDenied(const QString &appId, const QString &permission);
    void permissionRevoked(const QString &appId, const QString &permission);
    void permissionRequested(const QString &appId, const QString &permission);
    void promptActiveChanged();
    void currentRequestChanged();

  private:
    void    loadPermissions();
    void    savePermissions();
    QString getPermissionsFilePath();

    // Stored permissions: appId -> permission -> granted
    QMap<QString, QMap<QString, bool>> m_permissions;

    // Current permission request
    bool    m_promptActive;
    QString m_currentAppId;
    QString m_currentPermission;

    // Permission descriptions
    QMap<QString, QString> m_permissionDescriptions;

    class PortalManager   *m_portalManager;
};
