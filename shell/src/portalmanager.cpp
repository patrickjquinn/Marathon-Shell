#include "portalmanager.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDebug>
#include <QUuid>

// Portal constants
const QString PORTAL_SERVICE = "org.freedesktop.portal.Desktop";
const QString PORTAL_PATH = "/org/freedesktop/portal/desktop";
const QString PORTAL_ACCESS_INTERFACE = "org.freedesktop.portal.Access";
const QString PORTAL_CAMERA_INTERFACE = "org.freedesktop.portal.Camera";
const QString PORTAL_LOCATION_INTERFACE = "org.freedesktop.portal.Location";
const QString PORTAL_REQUEST_INTERFACE = "org.freedesktop.portal.Request";

PortalManager::PortalManager(QObject *parent)
    : QObject(parent)
    , m_portalsAvailable(false)
{
    checkPortals();
}

PortalManager::~PortalManager()
{
}

void PortalManager::checkPortals()
{
    // Use QDBusMessage directly to avoid introspection warnings (e.g. invalid property names in PowerProfileMonitor)
    QDBusMessage message = QDBusMessage::createMethodCall(PORTAL_SERVICE, PORTAL_PATH, 
                                                         "org.freedesktop.DBus.Properties", "Get");
    message << PORTAL_ACCESS_INTERFACE << "version";
    
    QDBusReply<QVariant> reply = QDBusConnection::sessionBus().call(message);
    
    if (reply.isValid()) {
        qInfo() << "[PortalManager] XDG Desktop Portal detected (version" << reply.value().toUInt() << ")";
        m_portalsAvailable = true;
    } else {
        // Try checking another interface if Access isn't available
        QDBusMessage camMessage = QDBusMessage::createMethodCall(PORTAL_SERVICE, PORTAL_PATH, 
                                                                "org.freedesktop.DBus.Properties", "Get");
        camMessage << PORTAL_CAMERA_INTERFACE << "version";
        
        QDBusReply<QVariant> camReply = QDBusConnection::sessionBus().call(camMessage);
        
        if (camReply.isValid()) {
            qInfo() << "[PortalManager] XDG Desktop Portal detected (Camera available)";
            m_portalsAvailable = true;
        } else {
            qWarning() << "[PortalManager] XDG Desktop Portal service found but interfaces not responding";
            m_portalsAvailable = false;
        }
    }
}

bool PortalManager::isPortalAvailable(const QString &portalName)
{
    if (!m_portalsAvailable) return false;
    
    if (portalName.isEmpty()) return true;
    
    // Check specific portal availability
    QString interface;
    if (portalName == "camera") interface = PORTAL_CAMERA_INTERFACE;
    else if (portalName == "location") interface = PORTAL_LOCATION_INTERFACE;
    else return true; // Assume available if generic
    
    QDBusMessage message = QDBusMessage::createMethodCall(PORTAL_SERVICE, PORTAL_PATH, 
                                                         "org.freedesktop.DBus.Properties", "Get");
    message << interface << "version";
    
    QDBusReply<QVariant> reply = QDBusConnection::sessionBus().call(message);
    return reply.isValid();
}

QString PortalManager::getRequestHandleToken(const QString &appId)
{
    // Generate a unique token for the request
    return QString("marathon_req_%1_%2").arg(appId).arg(QUuid::createUuid().toString(QUuid::Id128));
}

void PortalManager::requestCameraAccess(const QString &appId)
{
    if (!isPortalAvailable("camera")) {
        emit cameraAccessDenied(appId);
        return;
    }

    qInfo() << "[PortalManager] Requesting Camera access for" << appId << "via portal";

    QDBusMessage message = QDBusMessage::createMethodCall(PORTAL_SERVICE, PORTAL_PATH, 
                                                         PORTAL_CAMERA_INTERFACE, "AccessCamera");
    
    QVariantMap options;
    // options.insert("handle_token", getRequestHandleToken(appId)); // Optional, system can generate one
    
    message << options;
    
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    watcher->setProperty("appId", appId);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &PortalManager::onCameraRequestFinished);
}

// Helper class to handle portal responses
class PortalRequest : public QObject {
    Q_OBJECT
public:
    PortalRequest(const QString &path, const QString &appId, PortalManager *manager) 
        : QObject(manager), m_path(path), m_appId(appId), m_manager(manager) {
        QDBusConnection::sessionBus().connect(
            PORTAL_SERVICE, m_path, PORTAL_REQUEST_INTERFACE, "Response",
            this, SLOT(onResponse(uint, QVariantMap)));
    }
    
public slots:
    void onResponse(uint response, const QVariantMap &results) {
        m_manager->handlePortalResponse(m_path, m_appId, response, results);
        deleteLater();
    }
    
private:
    QString m_path;
    QString m_appId;
    PortalManager *m_manager;
};

#include "portalmanager.moc"

void PortalManager::onCameraRequestFinished(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<QDBusObjectPath> reply = *watcher;
    QString appId = watcher->property("appId").toString();
    
    if (reply.isError()) {
        qWarning() << "[PortalManager] Camera request error:" << reply.error().message();
        emit cameraAccessDenied(appId);
    } else {
        QString requestPath = reply.value().path();
        qInfo() << "[PortalManager] Camera request initiated, handle:" << requestPath;
        
        // Create helper to listen for response
        new PortalRequest(requestPath, appId, this);
        
        m_pendingCameraRequests.insert(requestPath, appId);
    }
    watcher->deleteLater();
}

void PortalManager::requestLocationAccess(const QString &appId)
{
    if (!isPortalAvailable("location")) {
        emit locationAccessDenied(appId);
        return;
    }

    qInfo() << "[PortalManager] Requesting Location access for" << appId << "via portal";

    QDBusMessage message = QDBusMessage::createMethodCall(PORTAL_SERVICE, PORTAL_PATH, 
                                                         PORTAL_LOCATION_INTERFACE, "CreateSession");
    
    QVariantMap options;
    options.insert("session_handle_token", getRequestHandleToken(appId));
    
    message << options;
    
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    watcher->setProperty("appId", appId);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &PortalManager::onLocationRequestFinished);
}

void PortalManager::onLocationRequestFinished(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<QDBusObjectPath> reply = *watcher;
    QString appId = watcher->property("appId").toString();
    
    if (reply.isError()) {
        qWarning() << "[PortalManager] Location session error:" << reply.error().message();
        emit locationAccessDenied(appId);
    } else {
        QString requestPath = reply.value().path();
        qInfo() << "[PortalManager] Location session created, handle:" << requestPath;
        
        // For location, we treat session creation as success for now
        emit locationAccessGranted(appId);
    }
    watcher->deleteLater();
}

void PortalManager::requestMicrophoneAccess(const QString &appId)
{
    emit microphoneAccessDenied(appId);
}

void PortalManager::onMicrophoneRequestFinished(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
}

void PortalManager::handlePortalResponse(const QString &path, const QString &appId, uint response, const QVariantMap &results)
{
    qInfo() << "[PortalManager] Received response from" << path << "Code:" << response;
    
    if (m_pendingCameraRequests.contains(path)) {
        m_pendingCameraRequests.remove(path);
        if (response == 0) {
            emit cameraAccessGranted(appId);
        } else {
            emit cameraAccessDenied(appId);
        }
    }
}
