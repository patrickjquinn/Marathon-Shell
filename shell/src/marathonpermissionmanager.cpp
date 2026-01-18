#include "marathonpermissionmanager.h"
#include "portalmanager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTimer>

MarathonPermissionManager::MarathonPermissionManager(QObject *parent)
    : QObject(parent)
    , m_promptActive(false) {
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
        {"system", "Access system-level features (restricted to system apps)"},
        {"terminal", "Run shell commands with full system access (DANGEROUS)"}};

    loadPermissions();

    m_portalManager = new PortalManager(this);
    m_batchTimer    = new QTimer(this);
    m_batchTimer->setSingleShot(true);
    m_batchTimer->setInterval(150); // 150ms debounce window

    connect(m_batchTimer, &QTimer::timeout, this,
            &MarathonPermissionManager::processPendingRequests);

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

void MarathonPermissionManager::requestPermissions(const QString     &appId,
                                                   const QStringList &permissions) {
    for (const QString &perm : permissions) {
        requestPermission(appId, perm);
    }
}

void MarathonPermissionManager::requestPermission(const QString &appId, const QString &permission) {
    qDebug() << "[MarathonPermissionManager] Permission requested:" << appId << permission;

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

    if (m_portalManager->isPortalAvailable(permission)) {
        qInfo() << "[MarathonPermissionManager] Delegating request to XDG Portal for" << permission;

        if (permission == "camera") {
            m_portalManager->requestCameraAccess(appId);
            return;
        } else if (permission == "location") {
            m_portalManager->requestLocationAccess(appId);
            return;
        }
    }

    // Buffer the request
    m_pendingRequests.append({appId, permission});

    // Reset debounce timer
    m_batchTimer->start();
}

void MarathonPermissionManager::processPendingRequests() {
    if (m_pendingRequests.isEmpty())
        return;

    // If a prompt is already active, do nothing (wait for it to close)
    if (m_promptActive)
        return;

    // Process requests for the FIRST app in the queue
    QString                              appId = m_pendingRequests.first().appId;

    QStringList                          batch;
    QMutableListIterator<PendingRequest> i(m_pendingRequests);
    while (i.hasNext()) {
        const PendingRequest &req = i.next();
        if (req.appId == appId) {
            if (!batch.contains(req.permission)) {
                batch.append(req.permission);
            }
            i.remove();
        }
    }

    if (batch.isEmpty()) {
        checkQueue(); // Should normally not happen
        return;
    }

    qDebug() << "[MarathonPermissionManager] Batching" << batch.size() << "permissions for"
             << appId;

    m_promptActive       = true;
    m_currentAppId       = appId;
    m_currentPermissions = batch;
    m_currentPermission  = batch.first(); // Legacy compatibility, though UI should switch to list

    emit promptActiveChanged();
    emit currentRequestChanged();

    // Still emit individual signals for compatibility if needed, but primarily the batch
    // signal
    emit permissionsRequested(appId, batch);

    qDebug() << "[MarathonPermissionManager] Showing custom permission batch prompt";
}

void MarathonPermissionManager::checkQueue() {
    if (!m_pendingRequests.isEmpty() && !m_promptActive) {
        // Schedule next processing
        QTimer::singleShot(50, this, &MarathonPermissionManager::processPendingRequests);
    }
}

void MarathonPermissionManager::setPermission(const QString &appId, const QString &permission,
                                              bool granted, bool remember) {
    setPermissions(appId, {permission}, granted, remember);
}

void MarathonPermissionManager::setPermissions(const QString &appId, const QStringList &permissions,
                                               bool granted, bool remember) {
    qDebug() << "[MarathonPermissionManager] Setting permissions:" << appId << permissions
             << granted << remember;

    if (remember) {
        if (!m_permissions.contains(appId)) {
            m_permissions[appId] = QMap<QString, bool>();
        }

        for (const QString &perm : permissions) {
            m_permissions[appId][perm] = granted;
        }
        savePermissions();
    }

    // Close prompt
    m_promptActive = false;
    m_currentAppId.clear();
    m_currentPermissions.clear();
    m_currentPermission.clear();

    emit promptActiveChanged();
    emit currentRequestChanged();

    // Emit results for each permission
    for (const QString &perm : permissions) {
        if (granted) {
            emit permissionGranted(appId, perm);
        } else {
            emit permissionDenied(appId, perm);
        }
    }

    // Check if there are more pending requests
    checkQueue();
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
        if (it.value()) {
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
