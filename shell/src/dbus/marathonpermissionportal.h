#pragma once

#include <QObject>
#include <QDBusContext>
#include <QString>
#include <QVariantMap>

class MarathonPermissionManager;

class MarathonPermissionPortal : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.PermissionPortal")

  public:
    explicit MarathonPermissionPortal(MarathonPermissionManager *permissionManager,
                                      QObject                   *parent = nullptr);

    bool registerService();

  public slots:
    // Check if caller has permission
    bool CheckPermission(const QString &permission);

    // Request permission (async - will show prompt if needed)
    void RequestPermission(const QString &permission);

    // Get caller's app ID
    QString GetCallerAppId();

  signals:
    // Emitted when permission is granted after request
    void PermissionGranted(const QString &permission);

    // Emitted when permission is denied after request
    void PermissionDenied(const QString &permission);

  private:
    QString                    getCallerAppId();
    qint64                     getCallerPid();
    QString                    resolveAppIdFromPid(qint64 pid);

    MarathonPermissionManager *m_permissionManager;
};
