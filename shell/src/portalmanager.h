#ifndef PORTALMANAGER_H
#define PORTALMANAGER_H

#include <QObject>

#include <QDBusPendingCallWatcher>
#include <QMap>
#include <QVariant>

class PortalManager : public QObject
{
    Q_OBJECT

public:
    explicit PortalManager(QObject *parent = nullptr);
    ~PortalManager();

    // Check if portals are available on the system
    bool isPortalAvailable(const QString &portalName = QString());
    
    // Request access via portal
    void requestCameraAccess(const QString &appId);
    void requestLocationAccess(const QString &appId);
    void requestMicrophoneAccess(const QString &appId);

signals:
    // Signals to notify PermissionManager of portal results
    void cameraAccessGranted(const QString &appId);
    void cameraAccessDenied(const QString &appId);
    
    void locationAccessGranted(const QString &appId);
    void locationAccessDenied(const QString &appId);
    
    void microphoneAccessGranted(const QString &appId);
    void microphoneAccessDenied(const QString &appId);

private slots:
    void onCameraRequestFinished(QDBusPendingCallWatcher *watcher);
    void onLocationRequestFinished(QDBusPendingCallWatcher *watcher);
    void onMicrophoneRequestFinished(QDBusPendingCallWatcher *watcher);
    
public:
    // Called by helper class
    void handlePortalResponse(const QString &path, const QString &appId, uint response, const QVariantMap &results);

private:
    bool m_portalsAvailable;

    
    // Map request handle paths to appIds to track pending requests
    QMap<QString, QString> m_pendingCameraRequests;
    QMap<QString, QString> m_pendingLocationRequests;
    QMap<QString, QString> m_pendingMicrophoneRequests;
    
    void checkPortals();
    QString getRequestHandleToken(const QString &appId);
};

#endif // PORTALMANAGER_H
