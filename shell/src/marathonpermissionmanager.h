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
    Q_PROPERTY(QStringList currentPermissions READ currentPermissions NOTIFY currentRequestChanged)

  public:
    enum PermissionStatus {
        NotRequested,
        Granted,
        Denied,
        Prompt
    };
    Q_ENUM(PermissionStatus)

    explicit MarathonPermissionManager(QObject *parent = nullptr);

    Q_INVOKABLE bool hasPermission(const QString &appId, const QString &permission);

    Q_INVOKABLE void requestPermission(const QString &appId, const QString &permission);
    Q_INVOKABLE void requestPermissions(const QString &appId, const QStringList &permissions);

    Q_INVOKABLE void setPermission(const QString &appId, const QString &permission, bool granted,
                                   bool remember = true);
    Q_INVOKABLE void setPermissions(const QString &appId, const QStringList &permissions,
                                    bool granted, bool remember = true);

    Q_INVOKABLE QStringList      getAppPermissions(const QString &appId);

    Q_INVOKABLE void             revokePermission(const QString &appId, const QString &permission);

    Q_INVOKABLE PermissionStatus getPermissionStatus(const QString &appId,
                                                     const QString &permission);

    Q_INVOKABLE QStringList      getAvailablePermissions();

    Q_INVOKABLE QString          getPermissionDescription(const QString &permission);

    bool                         promptActive() const {
        return m_promptActive;
    }
    QString currentAppId() const {
        return m_currentAppId;
    }
    QString currentPermission() const {
        return m_currentPermission;
    }
    QStringList currentPermissions() const {
        return m_currentPermissions;
    }

  signals:
    void permissionGranted(const QString &appId, const QString &permission);
    void permissionDenied(const QString &appId, const QString &permission);
    void permissionRevoked(const QString &appId, const QString &permission);
    void permissionRequested(const QString &appId, const QString &permission);
    void permissionsRequested(const QString &appId, const QStringList &permissions);
    void promptActiveChanged();
    void currentRequestChanged();

  private slots:
    void processPendingRequests();

  private:
    void                               loadPermissions();
    void                               savePermissions();
    QString                            getPermissionsFilePath();
    void                               checkQueue();

    QMap<QString, QMap<QString, bool>> m_permissions;

    bool                               m_promptActive;
    QString                            m_currentAppId;
    QString                            m_currentPermission;
    QStringList                        m_currentPermissions;

    QMap<QString, QString>             m_permissionDescriptions;

    class PortalManager               *m_portalManager;
    class QTimer                      *m_batchTimer;

    struct PendingRequest {
        QString appId;
        QString permission;
    };
    QList<PendingRequest> m_pendingRequests;
};
