#include "marathonappinstaller.h"
#include "marathonapppackager.h"
#include "marathonapppaths.h"
#include "marathonappverifier.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QDebug>
#include "marathon-core-native/src/lib.rs.h"
#include <algorithm>
#include <syslog.h>
#include <utility>   // std::as_const

MarathonAppInstaller::MarathonAppInstaller(MarathonAppRegistry *registry,
                                           MarathonAppScanner *scanner, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
    , m_scanner(scanner)
    , m_packager(new MarathonAppPackager(this))
    , m_verifier(new MarathonAppVerifier(this)) {
    qDebug() << "[MarathonAppInstaller] Initialized";

    connect(m_packager, &MarathonAppPackager::packagingProgress, this, [this](int percent) {
        qDebug() << "[MarathonAppInstaller] Packaging progress:" << percent << "%";
    });

    connect(m_packager, &MarathonAppPackager::extractionProgress, this, [this](int percent) {
        qDebug() << "[MarathonAppInstaller] Extraction progress:" << percent << "%";
    });
}

QString MarathonAppInstaller::getInstallDirectory() {
    return MarathonAppPaths::userInstalls();
}

bool MarathonAppInstaller::validateManifest(const QString &manifestPath) {
    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[MarathonAppInstaller] Cannot open manifest:" << manifestPath;
        return false;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[MarathonAppInstaller] JSON parse error:" << error.errorString();
        return false;
    }

    if (!doc.isObject()) {
        qWarning() << "[MarathonAppInstaller] Manifest is not a JSON object";
        return false;
    }

    QJsonObject obj = doc.object();

    if (!obj.contains("id") || !obj.contains("name") || !obj.contains("entryPoint")) {
        qWarning() << "[MarathonAppInstaller] Manifest missing required fields";
        return false;
    }

    return true;
}

static QStringList permissionsOf(const QJsonObject &manifest) {
    const QJsonArray array = manifest.value("permissions").toArray();
    QStringList      permissions;
    for (const auto &value : array)
        permissions.append(value.toString());
    permissions.removeDuplicates();
    return permissions;
}

bool MarathonAppInstaller::planInstall(const QJsonObject &manifest, const QString &signer,
                                       const QStringList &approved) {
    const QString     appId       = manifest.value("id").toString();
    const QStringList permissions = permissionsOf(manifest);

    QVariantList      disclosures;
    QStringList       undisclosed;
    for (const QString &id : permissions) {
        const QByteArray                             utf8 = id.toUtf8();
        const marathon::native::PermissionDisclosure d =
            marathon::native::describe_permission(rust::Str(utf8.constData(), utf8.size()));
        if (!d.known) {
            undisclosed.append(id);
            continue;
        }
        disclosures.append(
            QVariantMap{{"id", id},
                        {"label", QString::fromUtf8(d.label.data(), d.label.size())},
                        {"detail", QString::fromUtf8(d.detail.data(), d.detail.size())},
                        {"sensitive", d.sensitive}});
    }
    if (!undisclosed.isEmpty()) {
        const QString list = undisclosed.join(", ");
        qWarning() << "[MarathonAppInstaller] SECURITY: Undisclosed permissions:" << appId << list;
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Undisclosed permissions refused: app=%s perms=%s",
               appId.toUtf8().constData(), list.toUtf8().constData());
        emit installFailed(appId, "Permissions with no description: " + list);
        return false;
    }

    QFile       current(MarathonAppPaths::receiptPath(appId));
    const bool  isUpdate = current.open(QIODevice::ReadOnly);
    QStringList added;
    if (isUpdate) {
        const QStringList installed =
            permissionsOf(QJsonDocument::fromJson(current.readAll()).object());
        for (const QString &id : permissions) {
            if (!installed.contains(id))
                added.append(id);
        }
    }

    const QVariantMap plan{{"id", appId},
                           {"name", manifest.value("name").toString()},
                           {"version", manifest.value("version").toString()},
                           {"signer", signer},
                           {"update", isUpdate},
                           {"permissions", disclosures},
                           {"added", added}};
    emit              installPlanned(appId, plan);

    const bool consented = std::all_of(added.cbegin(), added.cend(),
                                       [&](const QString &id) { return approved.contains(id); });
    if (!consented) {
        const QString list = added.join(", ");
        qWarning() << "[MarathonAppInstaller] Update needs consent for new permissions:" << appId
                   << list;
        syslog(LOG_AUTH | LOG_NOTICE, "[SECURITY] Update held for consent: app=%s new perms=%s",
               appId.toUtf8().constData(), list.toUtf8().constData());
        emit installHeld(appId, plan);
        return false;
    }
    return true;
}

bool MarathonAppInstaller::copyDirectory(const QString &source, const QString &destination) {
    QDir sourceDir(source);
    if (!sourceDir.exists()) {
        qWarning() << "[MarathonAppInstaller] Source directory doesn't exist:" << source;
        return false;
    }

    QDir destDir(destination);
    if (!destDir.exists()) {
        destDir.mkpath(".");
    }

    QFileInfoList entries = sourceDir.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);

    for (const QFileInfo &entry : std::as_const(entries)) {
        QString srcPath = entry.absoluteFilePath();
        QString dstPath = destination + "/" + entry.fileName();

        if (entry.isDir()) {
            if (!copyDirectory(srcPath, dstPath)) {
                return false;
            }
        } else {
            if (!QFile::copy(srcPath, dstPath)) {
                qWarning() << "[MarathonAppInstaller] Failed to copy:" << srcPath << "to"
                           << dstPath;
                return false;
            }
        }
    }

    return true;
}

bool MarathonAppInstaller::removeDirectory(const QString &path) {
    QDir dir(path);
    if (!dir.exists()) {
        return true;
    }

    bool success = dir.removeRecursively();
    if (!success) {
        qWarning() << "[MarathonAppInstaller] Failed to remove directory:" << path;
    }

    return success;
}

// The receipt is what the user approved: the permissions the plan disclosed
// and, for an update, consented to. The scanner trusts it, not the manifest.
static bool writeReceipt(const QJsonObject &manifest, const QString &signer) {
    const QString     appId = manifest.value("id").toString();
    const QJsonObject receipt{{"id", appId},
                              {"version", manifest.value("version").toString()},
                              {"signer", signer},
                              {"permissions", QJsonArray::fromStringList(permissionsOf(manifest))}};
    QSaveFile         file(MarathonAppPaths::receiptPath(appId));
    return file.open(QIODevice::WriteOnly) && file.write(QJsonDocument(receipt).toJson()) > 0 &&
        file.commit();
}

bool MarathonAppInstaller::place(const QJsonObject &manifest, const QString &source,
                                 const QString &signer, bool move) {
    const QString appId = manifest.value("id").toString();
    if (QFile::exists(MarathonAppPaths::systemApps() + "/" + appId + "/manifest.json")) {
        emit installFailed(appId, "A system app has this id");
        return false;
    }

    const QString base = MarathonAppPaths::userInstalls();
    const QString dest = MarathonAppPaths::installDir(appId);
    QDir().mkpath(base);
    if (!QFileInfo(dest).absoluteFilePath().startsWith(QFileInfo(base).absoluteFilePath() + "/")) {
        qWarning() << "[MarathonAppInstaller] SECURITY: Path escape attempt detected:" << dest;
        emit installFailed(appId, "Security violation: installation path escape");
        return false;
    }
    if (!removeDirectory(dest)) {
        emit installFailed(appId, "Failed to remove existing installation");
        return false;
    }
    QDir().mkpath(dest);

    const QString files = MarathonAppPaths::filesDir(appId);
    if (!(move && QDir().rename(source, files)) && !copyDirectory(source, files)) {
        removeDirectory(dest);
        emit installFailed(appId, "Failed to copy app files");
        return false;
    }
    if (!writeReceipt(manifest, signer)) {
        removeDirectory(dest);
        emit installFailed(appId, "Failed to record the installation");
        return false;
    }

    emit installProgress(appId, 90);
    m_registry->unregisterApp(appId);
    m_scanner->scanApplications();
    emit installProgress(appId, 100);
    emit installComplete(appId);
    return true;
}

bool MarathonAppInstaller::installFromDirectory(const QString     &sourcePath,
                                                const QStringList &approvedPermissions) {
    qDebug() << "[MarathonAppInstaller] Installing from directory:" << sourcePath;

    const QByteArray sourceUtf8 = sourcePath.toUtf8();
    if (!MarathonAppVerifier::unsignedAllowed()) {
        qWarning() << "[MarathonAppInstaller] SECURITY: Unsigned directory install refused:"
                   << sourcePath;
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Unsigned directory install refused: dir=%s",
               sourceUtf8.constData());
        emit installFailed("unknown",
                           "A directory is not signed: install a signed package, or set "
                           "MARATHON_ALLOW_UNSIGNED=1 for development");
        return false;
    }
    syslog(LOG_AUTH | LOG_WARNING,
           "[SECURITY] Unsigned directory install allowed by MARATHON_ALLOW_UNSIGNED: dir=%s",
           sourceUtf8.constData());

    QString manifestPath = sourcePath + "/manifest.json";
    if (!validateManifest(manifestPath)) {
        emit installFailed("unknown", "Invalid or missing manifest.json");
        return false;
    }

    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit installFailed("unknown", "Failed to open manifest.json");
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    QString appId      = doc.object().value("id").toString();
    QString appName    = doc.object().value("name").toString();
    QString entryPoint = doc.object().value("entryPoint").toString();

    if (appId.isEmpty() || appId.contains("..") || appId.contains('/') || appId.contains('\\') ||
        appId.startsWith('.')) {
        qWarning() << "[MarathonAppInstaller] SECURITY: Invalid appId detected:" << appId;
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Path traversal blocked: appId=%s",
               appId.toUtf8().constData());
        emit installFailed("unknown", "Invalid app ID");
        return false;
    }

    if (!entryPoint.isEmpty()) {
        if (entryPoint.contains("..") || entryPoint.startsWith('/') ||
            entryPoint.startsWith('\\')) {
            qWarning() << "[MarathonAppInstaller] SECURITY: Invalid entryPoint detected:"
                       << entryPoint;
            syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Path traversal blocked: app=%s entryPoint=%s",
                   appId.toUtf8().constData(), entryPoint.toUtf8().constData());
            emit installFailed(appId, "Invalid entry point");
            return false;
        }
    }

    if (!planInstall(doc.object(), QString(), approvedPermissions))
        return false;

    emit installStarted(appId);
    emit installProgress(appId, 50);
    if (!place(doc.object(), sourcePath, QString(), false))
        return false;

    qDebug() << "[MarathonAppInstaller] Successfully installed:" << appName << "(" << appId << ")";
    return true;
}

bool MarathonAppInstaller::installFromPackage(const QString     &packagePath,
                                              const QStringList &approvedPermissions) {
    qDebug() << "[MarathonAppInstaller] Installing from package:" << packagePath;

    if (!QFile::exists(packagePath)) {
        emit installFailed("unknown", "Package file does not exist");
        return false;
    }

    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        emit installFailed("unknown", "Failed to create temporary directory");
        return false;
    }

    // Check and unpack a private copy, so the archive can't be swapped
    // between the signature check and extraction.
    const QString packageCopy = tempDir.path() + "/package.marathon";
    const QString signature   = packagePath + ".minisig";
    if (!QFile::copy(packagePath, packageCopy) ||
        (QFile::exists(signature) && !QFile::copy(signature, packageCopy + ".minisig"))) {
        emit installFailed("unknown", "Failed to read package");
        return false;
    }

    const MarathonAppVerifier::VerificationResult verifyResult =
        m_verifier->verifyPackage(packageCopy);
    if (verifyResult != MarathonAppVerifier::Valid &&
        verifyResult != MarathonAppVerifier::AllowedUnsigned) {
        QString error = "Package verification failed: " + m_verifier->lastError();
        qWarning() << "[MarathonAppInstaller]" << error;
        emit installFailed("unknown", error);
        return false;
    }

    emit    installProgress("verifying", 30);

    QString tempExtractPath = tempDir.path() + "/extracted";

    qDebug() << "[MarathonAppInstaller] Extracting to temp:" << tempExtractPath;

    if (!m_packager->extractPackage(packageCopy, tempExtractPath)) {
        QString error = "Failed to extract package: " + m_packager->lastError();
        emit    installFailed("unknown", error);
        return false;
    }

    emit    installProgress("extracting", 50);

    QString manifestPath = tempExtractPath + "/manifest.json";
    QFile   manifestFile(manifestPath);
    if (!manifestFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit installFailed("unknown", "Failed to read manifest.json");
        return false;
    }

    QJsonDocument doc = QJsonDocument::fromJson(manifestFile.readAll());
    manifestFile.close();

    if (!doc.isObject()) {
        emit installFailed("unknown", "Invalid manifest.json");
        return false;
    }

    QString appId      = doc.object().value("id").toString();
    QString appName    = doc.object().value("name").toString();
    QString entryPoint = doc.object().value("entryPoint").toString();

    if (appId.isEmpty() || appId.contains("..") || appId.contains('/') || appId.contains('\\') ||
        appId.startsWith('.')) {
        qWarning() << "[MarathonAppInstaller] SECURITY: Invalid appId in package:" << appId;
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Path traversal blocked in package: appId=%s",
               appId.toUtf8().constData());
        emit installFailed("unknown", "Invalid app ID");
        return false;
    }

    if (!entryPoint.isEmpty()) {
        if (entryPoint.contains("..") || entryPoint.startsWith('/') ||
            entryPoint.startsWith('\\')) {
            qWarning() << "[MarathonAppInstaller] SECURITY: Invalid entryPoint in package:"
                       << entryPoint;
            syslog(LOG_AUTH | LOG_ALERT,
                   "[SECURITY] Path traversal blocked in package: app=%s entryPoint=%s",
                   appId.toUtf8().constData(), entryPoint.toUtf8().constData());
            emit installFailed(appId, "Invalid entry point");
            return false;
        }
    }

    if (!planInstall(doc.object(), m_verifier->signerKeyId(), approvedPermissions))
        return false;

    qDebug() << "[MarathonAppInstaller] Installing app:" << appName << "(" << appId << ")";
    emit installStarted(appId);
    emit installProgress(appId, 60);
    if (!place(doc.object(), tempExtractPath, m_verifier->signerKeyId(), true))
        return false;

    qDebug() << "[MarathonAppInstaller] Successfully installed:" << appName << "(" << appId << ")";
    return true;
}

bool MarathonAppInstaller::canUninstall(const QString &appId) {
    const MarathonAppRegistry::AppInfo *info = m_registry->getAppInfo(appId);
    return info && !info->isProtected && info->absolutePath == MarathonAppPaths::filesDir(appId);
}

bool MarathonAppInstaller::uninstallApp(const QString &appId) {
    qDebug() << "[MarathonAppInstaller] Uninstalling app:" << appId;

    if (!m_registry->hasApp(appId)) {
        emit uninstallFailed(appId, "App not found");
        return false;
    }
    if (!canUninstall(appId)) {
        const QString error = "Cannot uninstall a protected or system app";
        qWarning() << "[MarathonAppInstaller]" << error << ":" << appId;
        emit uninstallFailed(appId, error);
        return false;
    }

    if (!removeDirectory(MarathonAppPaths::installDir(appId))) {
        emit uninstallFailed(appId, "Failed to remove app files");
        return false;
    }

    m_registry->unregisterApp(appId);
    emit uninstallComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully uninstalled:" << appId;
    return true;
}
