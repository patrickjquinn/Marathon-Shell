#include "marathonappinstaller.h"
#include "marathonapppackager.h"
#include "marathonappverifier.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QDebug>

MarathonAppInstaller::MarathonAppInstaller(MarathonAppRegistry *registry,
                                           MarathonAppScanner *scanner, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
    , m_scanner(scanner)
    , m_packager(new MarathonAppPackager(this))
    , m_verifier(new MarathonAppVerifier(this)) {
    qDebug() << "[MarathonAppInstaller] Initialized";

    // Connect packager signals
    connect(m_packager, &MarathonAppPackager::packagingProgress, this, [this](int percent) {
        // Forward packaging progress
        qDebug() << "[MarathonAppInstaller] Packaging progress:" << percent << "%";
    });

    connect(m_packager, &MarathonAppPackager::extractionProgress, this, [this](int percent) {
        // Forward extraction progress
        qDebug() << "[MarathonAppInstaller] Extraction progress:" << percent << "%";
    });
}

QString MarathonAppInstaller::getTargetInstallPath() {
    QString homeDir = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return homeDir + "/.local/share/marathon-apps";
}

QString MarathonAppInstaller::getInstallDirectory() {
    return getTargetInstallPath();
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

    // Validate required fields
    if (!obj.contains("id") || !obj.contains("name") || !obj.contains("entryPoint")) {
        qWarning() << "[MarathonAppInstaller] Manifest missing required fields";
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

    for (const QFileInfo &entry : entries) {
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

bool MarathonAppInstaller::installFromDirectory(const QString &sourcePath) {
    qDebug() << "[MarathonAppInstaller] Installing from directory:" << sourcePath;

    // Validate manifest
    QString manifestPath = sourcePath + "/manifest.json";
    if (!validateManifest(manifestPath)) {
        emit installFailed("unknown", "Invalid or missing manifest.json");
        return false;
    }

    // Parse manifest to get app ID
    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit installFailed("unknown", "Failed to open manifest.json");
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    QString appId   = doc.object().value("id").toString();
    QString appName = doc.object().value("name").toString();

    emit    installStarted(appId);

    // Check if already installed
    if (m_registry->hasApp(appId)) {
        qDebug() << "[MarathonAppInstaller] App already installed, updating:" << appId;
    }

    // Determine destination
    QString installBase = getTargetInstallPath();
    QString destPath    = installBase + "/" + appId;

    // Remove existing installation
    if (QDir(destPath).exists()) {
        if (!removeDirectory(destPath)) {
            emit installFailed(appId, "Failed to remove existing installation");
            return false;
        }
    }

    emit installProgress(appId, 50);

    // Copy directory
    if (!copyDirectory(sourcePath, destPath)) {
        emit installFailed(appId, "Failed to copy app files");
        return false;
    }

    emit installProgress(appId, 90);

    // Rescan applications
    m_scanner->scanApplications();

    emit installProgress(appId, 100);
    emit installComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully installed:" << appName << "(" << appId << ")";
    return true;
}

bool MarathonAppInstaller::installFromPackage(const QString &packagePath) {
    qDebug() << "[MarathonAppInstaller] Installing from package:" << packagePath;

    // Check if package exists
    if (!QFile::exists(packagePath)) {
        emit installFailed("unknown", "Package file does not exist");
        return false;
    }

    // Create temporary directory for extraction
    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        emit installFailed("unknown", "Failed to create temporary directory");
        return false;
    }

    QString tempExtractPath = tempDir.path() + "/extracted";

    qDebug() << "[MarathonAppInstaller] Extracting to temp:" << tempExtractPath;

    // Extract package
    if (!m_packager->extractPackage(packagePath, tempExtractPath)) {
        QString error = "Failed to extract package: " + m_packager->lastError();
        emit    installFailed("unknown", error);
        return false;
    }

    emit installProgress("extracting", 30);

    // Verify package signature
    qDebug() << "[MarathonAppInstaller] Verifying package signature...";
    MarathonAppVerifier::VerificationResult verifyResult =
        m_verifier->verifyDirectory(tempExtractPath);

    if (verifyResult != MarathonAppVerifier::Valid) {
        QString error = "Package verification failed: " + m_verifier->lastError();
        qWarning() << "[MarathonAppInstaller]" << error;
        emit installFailed("unknown", error);
        return false;
    }

    emit installProgress("verifying", 50);

    // Read manifest to get app ID
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

    QString appId   = doc.object().value("id").toString();
    QString appName = doc.object().value("name").toString();

    if (appId.isEmpty()) {
        emit installFailed("unknown", "App ID missing in manifest");
        return false;
    }

    qDebug() << "[MarathonAppInstaller] Installing app:" << appName << "(" << appId << ")";
    emit installStarted(appId);
    emit installProgress(appId, 60);

    // Check if already installed
    if (m_registry->hasApp(appId)) {
        qDebug() << "[MarathonAppInstaller] App already installed, updating:" << appId;
    }

    // Determine destination
    QString installBase = getTargetInstallPath();
    QString destPath    = installBase + "/" + appId;

    // Remove existing installation
    if (QDir(destPath).exists()) {
        if (!removeDirectory(destPath)) {
            emit installFailed(appId, "Failed to remove existing installation");
            return false;
        }
    }

    emit installProgress(appId, 75);

    // Move extracted files to destination
    if (!QDir().rename(tempExtractPath, destPath)) {
        // If rename fails, try copy
        if (!copyDirectory(tempExtractPath, destPath)) {
            emit installFailed(appId, "Failed to copy app files to installation directory");
            return false;
        }
    }

    emit installProgress(appId, 90);

    // Rescan applications
    m_scanner->scanApplications();

    emit installProgress(appId, 100);
    emit installComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully installed:" << appName << "(" << appId << ")";
    return true;
}

bool MarathonAppInstaller::canUninstall(const QString &appId) {
    return !m_registry->isProtected(appId);
}

bool MarathonAppInstaller::uninstallApp(const QString &appId) {
    qDebug() << "[MarathonAppInstaller] Uninstalling app:" << appId;

    // Check if protected
    if (m_registry->isProtected(appId)) {
        QString error = "Cannot uninstall protected system app";
        qWarning() << "[MarathonAppInstaller]" << error << ":" << appId;
        emit uninstallFailed(appId, error);
        return false;
    }

    // Check if installed
    if (!m_registry->hasApp(appId)) {
        emit uninstallFailed(appId, "App not found");
        return false;
    }

    // Get app info
    QVariantMap appInfo = m_registry->getApp(appId);
    QString     appPath = appInfo.value("absolutePath").toString();

    if (appPath.isEmpty()) {
        emit uninstallFailed(appId, "App path not found");
        return false;
    }

    // Remove directory
    if (!removeDirectory(appPath)) {
        emit uninstallFailed(appId, "Failed to remove app files");
        return false;
    }

    // Rescan to update registry
    m_scanner->scanApplications();

    emit uninstallComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully uninstalled:" << appId;
    return true;
}
