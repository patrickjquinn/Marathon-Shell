#include "marathonpermissionmanager.h"
#include "portalmanager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>

MarathonPermissionManager::MarathonPermissionManager(QObject *parent)
    : QObject(parent)
    , m_promptActive(false) {
    // Initialize permission descriptions
    m_permissionDescriptions = {
        {"network", "Access the internet and make network connections"},
        {"location", "Access your device's location"},
        {"camera", "Access the camera to take photos and videos"},
        {"microphone", "Record audio using the microphone"},
        {"contacts", "Read and write your contacts"},
        {"calendar", "Read and write calendar events"},
        {"storage", "Read and write files on your device"},
        {"notifications", "Show notifications"},
        {"telephony", "Make and receive phone calls"},
        {"sms", "Send and receive SMS messages"},
        {"bluetooth", "Connect to Bluetooth devices"},
        {"system", "Access system-level features (restricted to system apps)"}};

    loadPermissions();

    // Initialize Portal Manager
    m_portalManager = new PortalManager(this);

    // Connect Portal signals
    connect(m_portalManager, &PortalManager::cameraAccessGranted, this,
            [this](const QString &appId) { setPermission(appId, "camera", true, true); });
    connect(m_portalManager, &PortalManager::cameraAccessDenied, this,
            [this](const QString &appId) { setPermission(appId, "camera", false, true); });

    connect(m_portalManager, &PortalManager::locationAccessGranted, this,
            [this](const QString &appId) { setPermission(appId, "location", true, true); });
    connect(m_portalManager, &PortalManager::locationAccessDenied, this,
            [this](const QString &appId) { setPermission(appId, "location", false, true); });

    qDebug() << "[MarathonPermissionManager] Initialized";
}

QString MarathonPermissionManager::getPermissionsFilePath() {
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    QDir    dir(configDir + "/marathon");
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return configDir + "/marathon/app-permissions.json";
}

void MarathonPermissionManager::loadPermissions() {
    QString filePath = getPermissionsFilePath();
    QFile   file(filePath);

    if (!file.exists()) {
        qDebug() << "[MarathonPermissionManager] No existing permissions file, starting fresh";
        return;
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[MarathonPermissionManager] Failed to open permissions file";
        return;
    }

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(file.readAll(), &error);
    file.close();

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[MarathonPermissionManager] Failed to parse permissions:"
                   << error.errorString();
        return;
    }

    if (!doc.isObject()) {
        qWarning() << "[MarathonPermissionManager] Permissions file is not a JSON object";
        return;
    }

    QJsonObject root = doc.object();

    // Load permissions for each app
    for (const QString &appId : root.keys()) {
        QJsonObject         appPerms = root.value(appId).toObject();
        QMap<QString, bool> permissions;

        for (const QString &permission : appPerms.keys()) {
            permissions[permission] = appPerms.value(permission).toBool();
        }

        m_permissions[appId] = permissions;
    }

    qDebug() << "[MarathonPermissionManager] Loaded permissions for" << m_permissions.size()
             << "apps";
}

void MarathonPermissionManager::savePermissions() {
    QString     filePath = getPermissionsFilePath();
    QJsonObject root;

    // Save permissions for each app
    for (auto it = m_permissions.constBegin(); it != m_permissions.constEnd(); ++it) {
        QString                    appId = it.key();
        QJsonObject                appPerms;

        const QMap<QString, bool> &permissions = it.value();
        for (auto permIt = permissions.constBegin(); permIt != permissions.constEnd(); ++permIt) {
            appPerms[permIt.key()] = permIt.value();
        }

        root[appId] = appPerms;
    }

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[MarathonPermissionManager] Failed to save permissions";
        return;
    }

    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();

    qDebug() << "[MarathonPermissionManager] Saved permissions";
}

bool MarathonPermissionManager::hasPermission(const QString &appId, const QString &permission) {
    if (!m_permissions.contains(appId)) {
        return false;
    }

    const QMap<QString, bool> &appPerms = m_permissions[appId];
    if (!appPerms.contains(permission)) {
        return false;
    }

    return appPerms[permission];
}

void MarathonPermissionManager::requestPermission(const QString &appId, const QString &permission) {
    qDebug() << "[MarathonPermissionManager] Permission requested:" << appId << permission;

    // Check if already granted or denied
    PermissionStatus status = getPermissionStatus(appId, permission);

    if (status == Granted) {
        qDebug() << "[MarathonPermissionManager] Permission already granted";
        emit permissionGranted(appId, permission);
        return;
    }

    if (status == Denied) {
        qDebug() << "[MarathonPermissionManager] Permission already denied";
        emit permissionDenied(appId, permission);
        return;
    }

    // Try to use XDG Portal if available
    if (m_portalManager->isPortalAvailable(permission)) {
        qInfo() << "[MarathonPermissionManager] Delegating request to XDG Portal for" << permission;

        if (permission == "camera") {
            m_portalManager->requestCameraAccess(appId);
            return;
        } else if (permission == "location") {
            m_portalManager->requestLocationAccess(appId);
            return;
        }
        // Fall through for other permissions not yet supported by our PortalManager wrapper
    }

    // Fallback to custom dialog
    m_promptActive      = true;
    m_currentAppId      = appId;
    m_currentPermission = permission;

    emit promptActiveChanged();
    emit currentRequestChanged();
    emit permissionRequested(appId, permission);

    qDebug() << "[MarathonPermissionManager] Showing custom permission prompt";
}

void MarathonPermissionManager::setPermission(const QString &appId, const QString &permission,
                                              bool granted, bool remember) {
    qDebug() << "[MarathonPermissionManager] Setting permission:" << appId << permission << granted
             << remember;

    if (remember) {
        // Store permanently
        if (!m_permissions.contains(appId)) {
            m_permissions[appId] = QMap<QString, bool>();
        }

        m_permissions[appId][permission] = granted;
        savePermissions();
    }

    // Hide prompt
    m_promptActive = false;
    m_currentAppId.clear();
    m_currentPermission.clear();
    emit promptActiveChanged();
    emit currentRequestChanged();

    // Emit appropriate signal
    if (granted) {
        emit permissionGranted(appId, permission);
    } else {
        emit permissionDenied(appId, permission);
    }
}

void MarathonPermissionManager::revokePermission(const QString &appId, const QString &permission) {
    qDebug() << "[MarathonPermissionManager] Revoking permission:" << appId << permission;

    if (m_permissions.contains(appId)) {
        m_permissions[appId].remove(permission);
        savePermissions();
        emit permissionRevoked(appId, permission);
    }
}

QStringList MarathonPermissionManager::getAppPermissions(const QString &appId) {
    if (!m_permissions.contains(appId)) {
        return QStringList();
    }

    QStringList                permissions;
    const QMap<QString, bool> &appPerms = m_permissions[appId];

    for (auto it = appPerms.constBegin(); it != appPerms.constEnd(); ++it) {
        if (it.value()) { // Only include granted permissions
            permissions.append(it.key());
        }
    }

    return permissions;
}

MarathonPermissionManager::PermissionStatus
MarathonPermissionManager::getPermissionStatus(const QString &appId, const QString &permission) {
    if (!m_permissions.contains(appId)) {
        return NotRequested;
    }

    const QMap<QString, bool> &appPerms = m_permissions[appId];
    if (!appPerms.contains(permission)) {
        return NotRequested;
    }

    return appPerms[permission] ? Granted : Denied;
}

QStringList MarathonPermissionManager::getAvailablePermissions() {
    return m_permissionDescriptions.keys();
}

QString MarathonPermissionManager::getPermissionDescription(const QString &permission) {
    return m_permissionDescriptions.value(permission, "Unknown permission");
}
