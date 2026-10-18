#include "marathonpermissionmanager.h"
#include "marathonappregistry.h"
#include <QJSEngine>
#include <QQmlEngine>
#include "portalmanager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTimer>
#include <algorithm>
#include <utility>   // std::as_const

MarathonPermissionManager *MarathonPermissionManager::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new MarathonPermissionManager(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}
MarathonPermissionManager::MarathonPermissionManager(QObject *parent)
    : QObject(parent)
    , m_promptActive(false) {
    const QList<MarathonManifest::Permission> vocabulary = MarathonManifest::permissions();
    for (const MarathonManifest::Permission &p : vocabulary)
        m_vocabulary.insert(p.name, p);

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

    const auto appIds = root.keys();
    for (const QString &appId : appIds) {
        QJsonObject         appPerms = root.value(appId).toObject();
        QMap<QString, bool> permissions;

        const auto permissionKeys = appPerms.keys();
        for (const QString &permission : permissionKeys) {
            permissions[canonical(permission)] = appPerms.value(permission).toBool();
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
        const QString             &appId = it.key();
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

void MarathonPermissionManager::setAppRegistry(MarathonAppRegistry *registry) {
    m_registry = registry;
}

QString MarathonPermissionManager::canonical(const QString &permission) {
    const QString name = MarathonManifest::canonicalPermission(permission);
    return name.isEmpty() ? permission : name;
}

const MarathonAppRegistry::AppInfo *MarathonPermissionManager::appInfo(const QString &appId) const {
    return m_registry ? m_registry->getAppInfo(appId) : nullptr;
}

bool MarathonPermissionManager::declares(const MarathonAppRegistry::AppInfo &app,
                                         const QString                      &permission) {
    return std::any_of(app.permissions.cbegin(), app.permissions.cend(),
                       [&](const QString &p) { return canonical(p) == permission; });
}

// Restricted permissions are held only by protected system apps.
bool MarathonPermissionManager::isRefused(const MarathonAppRegistry::AppInfo *app,
                                          const QString                      &permission) const {
    const auto it = m_vocabulary.constFind(permission);
    return it != m_vocabulary.constEnd() && it->restricted && !(app && app->isProtected);
}

bool MarathonPermissionManager::hasPermission(const QString &appId, const QString &permission) {
    return getPermissionStatus(appId, permission) == Granted;
}

void MarathonPermissionManager::forgetApp(const QString &appId) {
    dismissForApp(appId);
    if (m_permissions.remove(appId) > 0)
        savePermissions();
}

void MarathonPermissionManager::requestPermissions(const QString     &appId,
                                                   const QStringList &permissions) {
    for (const QString &perm : permissions) {
        requestPermission(appId, perm);
    }
}

void MarathonPermissionManager::requestDeclaredPermissions(const QString &appId) {
    if (const MarathonAppRegistry::AppInfo *app = appInfo(appId))
        requestPermissions(appId, app->permissions);
}

QString MarathonPermissionManager::askIfUndecided(const QString     &appId,
                                                  const QStringList &permissions) {
    const MarathonAppRegistry::AppInfo *app = appInfo(appId);
    if (!app)
        return {};
    for (const QString &requested : permissions) {
        const QString permission = canonical(requested);
        if (getPermissionStatus(appId, permission) == NotRequested) {
            requestPermission(appId, permission);
            return permission;
        }
    }
    return {};
}

void MarathonPermissionManager::requestPermission(const QString &appId, const QString &requested) {
    const QString permission = canonical(requested);
    qDebug() << "[MarathonPermissionManager] Permission requested:" << appId << permission;

    const MarathonAppRegistry::AppInfo *app = appInfo(appId);
    if (app && !declares(*app, permission)) {
        qWarning() << "[MarathonPermissionManager] SECURITY: undeclared permission requested:"
                   << appId << permission;
        emit permissionDenied(appId, permission);
        return;
    }

    PermissionStatus status = getPermissionStatus(appId, permission);
    // A refusal the user has not been shown yet goes to the prompt.
    const bool untold =
        isRefused(app, permission) && !m_permissions.value(appId).contains(permission);

    if (status == Granted) {
        qDebug() << "[MarathonPermissionManager] Permission already granted";
        emit permissionGranted(appId, permission);
        return;
    }

    if (status == Denied && !untold) {
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

    // Re-check each buffered request against the CURRENT decision before
    // batching it. requestPermission() checks status only at request time, so
    // anything that arrived while an earlier prompt was open was never
    // re-examined: the user granted storage in the first prompt and was then
    // asked for storage again the moment it closed. Browser did exactly that
    // -- one dialog for "storage and network", then a second for "storage".
    QStringList                          batch;
    QStringList                          refused;
    QStringList                          alreadyGranted;
    QStringList                          alreadyDenied;
    const MarathonAppRegistry::AppInfo  *app = appInfo(appId);
    QMutableListIterator<PendingRequest> i(m_pendingRequests);
    while (i.hasNext()) {
        const PendingRequest &req = i.next();
        if (req.appId != appId)
            continue;

        const PermissionStatus status = getPermissionStatus(appId, req.permission);
        if (isRefused(app, req.permission) &&
            !m_permissions.value(appId).contains(req.permission)) {
            if (!refused.contains(req.permission))
                refused.append(req.permission);
        } else if (status == Granted) {
            if (!alreadyGranted.contains(req.permission))
                alreadyGranted.append(req.permission);
        } else if (status == Denied) {
            if (!alreadyDenied.contains(req.permission))
                alreadyDenied.append(req.permission);
        } else if (!batch.contains(req.permission)) {
            batch.append(req.permission);
        }
        i.remove();
    }

    // Emit after draining the queue -- these signals can re-enter.
    for (const QString &perm : alreadyGranted)
        emit permissionGranted(appId, perm);
    for (const QString &perm : alreadyDenied)
        emit permissionDenied(appId, perm);

    if (batch.isEmpty() && refused.isEmpty()) {
        // Everything buffered for this app was already decided; move on to
        // the next app rather than showing an empty prompt.
        checkQueue();
        return;
    }

    qDebug() << "[MarathonPermissionManager] Batching" << batch.size() << "permissions for"
             << appId;

    m_promptActive       = true;
    m_currentAppId       = appId;
    m_currentPermissions = batch;
    m_currentRefused     = refused;
    m_currentPermission  = batch.value(0); // Legacy compatibility, though UI should switch to list

    emit promptActiveChanged();
    emit currentRequestChanged();

    // Still emit individual signals for compatibility if needed, but primarily the batch
    // signal
    emit permissionsRequested(appId, batch);

    qDebug() << "[MarathonPermissionManager] Showing custom permission batch prompt";
}

void MarathonPermissionManager::respond(bool granted) {
    if (!m_promptActive)
        return;
    const QString     appId   = m_currentAppId;
    const QStringList asked   = m_currentPermissions;
    const QStringList refused = m_currentRefused;
    // Stored as denied: the user has been told, so it is not shown again.
    for (const QString &permission : refused)
        m_permissions[appId][permission] = false;
    m_currentRefused.clear();
    if (asked.isEmpty()) {
        savePermissions();
        closePrompt();
        checkQueue();
    } else {
        setPermissions(appId, asked, granted, true);
    }
    for (const QString &permission : refused)
        emit permissionDenied(appId, permission);
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

    if (!m_permissions.contains(appId)) {
        m_permissions[appId] = QMap<QString, bool>();
    }

    for (const QString &perm : permissions) {
        m_permissions[appId][canonical(perm)] = granted;
    }

    if (remember) {
        savePermissions();
    }

    // Answers only what they decide: a grant for another app (Settings, a
    // portal) must not close this prompt and lose its requests.
    if (m_promptActive && appId == m_currentAppId) {
        for (const QString &perm : permissions)
            m_currentPermissions.removeAll(canonical(perm));
        if (m_currentPermissions.isEmpty() && m_currentRefused.isEmpty()) {
            closePrompt();
        } else {
            m_currentPermission = m_currentPermissions.value(0);
            emit currentRequestChanged();
        }
    }

    for (const QString &perm : permissions) {
        if (hasPermission(appId, perm)) {
            emit permissionGranted(appId, canonical(perm));
        } else {
            emit permissionDenied(appId, canonical(perm));
        }
    }

    // Check if there are more pending requests
    checkQueue();
}

void MarathonPermissionManager::dismissAll() {
    if (!m_promptActive && m_pendingRequests.isEmpty())
        return;

    qDebug() << "[MarathonPermissionManager] Dismissing all: active prompt for" << m_currentAppId
             << "+" << m_pendingRequests.size() << "pending requests";

    m_pendingRequests.clear();
    m_batchTimer->stop();
    closePrompt();
}

void MarathonPermissionManager::closePrompt() {
    m_promptActive = false;
    m_currentAppId.clear();
    m_currentPermissions.clear();
    m_currentRefused.clear();
    m_currentPermission.clear();
    emit promptActiveChanged();
    emit currentRequestChanged();
}

void MarathonPermissionManager::dismissForApp(const QString &appId) {
    if (appId.isEmpty())
        return;

    const qsizetype droppedFromQueue =
        m_pendingRequests.removeIf([&appId](const PendingRequest &r) { return r.appId == appId; });

    const bool clearedActive = m_promptActive && m_currentAppId == appId;
    if (clearedActive) {
        qDebug() << "[MarathonPermissionManager] App exited — dropping active prompt for" << appId;
        closePrompt();
        checkQueue();
    } else if (droppedFromQueue > 0) {
        qDebug() << "[MarathonPermissionManager] App exited — dropped" << droppedFromQueue
                 << "queued prompt(s) for" << appId;
    }
}

void MarathonPermissionManager::revokePermission(const QString &appId, const QString &requested) {
    const QString permission = canonical(requested);
    qDebug() << "[MarathonPermissionManager] Revoking permission:" << appId << permission;

    if (m_permissions.contains(appId)) {
        m_permissions[appId].remove(permission);
        savePermissions();
        emit permissionRevoked(appId, permission);
    }
}

QStringList MarathonPermissionManager::getAppPermissions(const QString &appId) {
    QStringList granted;
    for (auto it = m_vocabulary.keyBegin(); it != m_vocabulary.keyEnd(); ++it) {
        if (hasPermission(appId, *it))
            granted.append(*it);
    }
    return granted;
}

// An app holds only what it declared: in its read-only manifest for a
// system app, in the install receipt for any other. Apps the registry does
// not know (portal and GeoClue callers) only have what was stored.
MarathonPermissionManager::PermissionStatus
MarathonPermissionManager::getPermissionStatus(const QString &appId, const QString &requested) {
    const QString                       permission = canonical(requested);
    const MarathonAppRegistry::AppInfo *app        = appInfo(appId);
    if ((app && !declares(*app, permission)) || isRefused(app, permission))
        return Denied;
    const auto stored = m_permissions.value(appId);
    if (stored.contains(permission))
        return stored.value(permission) ? Granted : Denied;
    if (app && app->isProtected)
        return Granted;
    return NotRequested;
}

QStringList MarathonPermissionManager::getAvailablePermissions() {
    return m_vocabulary.keys();
}

QString MarathonPermissionManager::getPermissionLabel(const QString &permission) {
    const auto it = m_vocabulary.constFind(MarathonManifest::canonicalPermission(permission));
    return it == m_vocabulary.constEnd() ? permission : it->label;
}

QString MarathonPermissionManager::getPermissionDescription(const QString &permission) {
    const auto it = m_vocabulary.constFind(MarathonManifest::canonicalPermission(permission));
    return it == m_vocabulary.constEnd() ? QStringLiteral("Unknown permission") : it->description;
}
