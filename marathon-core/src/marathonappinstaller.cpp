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
#include <syslog.h>

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

    emit installStarted(appId);

    if (m_registry->hasApp(appId)) {
        qDebug() << "[MarathonAppInstaller] App already installed, updating:" << appId;
    }

    QString   installBase = getTargetInstallPath();
    QString   destPath    = installBase + "/" + appId;

    QFileInfo destInfo(destPath);
    QString   canonicalDest = destInfo.absoluteFilePath();
    QFileInfo baseInfo(installBase);
    QString   canonicalBase = baseInfo.canonicalFilePath();

    if (!canonicalBase.isEmpty() && !canonicalDest.startsWith(canonicalBase + "/")) {
        qWarning() << "[MarathonAppInstaller] SECURITY: Path escape attempt detected:"
                   << "dest=" << canonicalDest << "base=" << canonicalBase;
        emit installFailed(appId, "Security violation: installation path escape");
        return false;
    }

    if (QDir(destPath).exists()) {
        if (!removeDirectory(destPath)) {
            emit installFailed(appId, "Failed to remove existing installation");
            return false;
        }
    }

    emit installProgress(appId, 50);

    if (!copyDirectory(sourcePath, destPath)) {
        emit installFailed(appId, "Failed to copy app files");
        return false;
    }

    emit installProgress(appId, 90);

    m_scanner->scanApplications();

    emit installProgress(appId, 100);
    emit installComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully installed:" << appName << "(" << appId << ")";
    return true;
}

bool MarathonAppInstaller::installFromPackage(const QString &packagePath) {
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

    QString tempExtractPath = tempDir.path() + "/extracted";

    qDebug() << "[MarathonAppInstaller] Extracting to temp:" << tempExtractPath;

    if (!m_packager->extractPackage(packagePath, tempExtractPath)) {
        QString error = "Failed to extract package: " + m_packager->lastError();
        emit    installFailed("unknown", error);
        return false;
    }

    emit installProgress("extracting", 30);

    qDebug() << "[MarathonAppInstaller] Verifying package signature...";
    MarathonAppVerifier::VerificationResult verifyResult =
        m_verifier->verifyDirectory(tempExtractPath);

    if (verifyResult != MarathonAppVerifier::Valid) {
        QString error = "Package verification failed: " + m_verifier->lastError();
        qWarning() << "[MarathonAppInstaller]" << error;
        emit installFailed("unknown", error);
        return false;
    }

    emit    installProgress("verifying", 50);

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

    if (m_registry->hasApp(appId)) {
        qDebug() << "[MarathonAppInstaller] App already installed, updating:" << appId;
    }

    QString installBase = getTargetInstallPath();
    QString destPath    = installBase + "/" + appId;

    if (QDir(destPath).exists()) {
        if (!removeDirectory(destPath)) {
            emit installFailed(appId, "Failed to remove existing installation");
            return false;
        }
    }

    emit installProgress(appId, 75);

    if (!QDir().rename(tempExtractPath, destPath)) {

        if (!copyDirectory(tempExtractPath, destPath)) {
            emit installFailed(appId, "Failed to copy app files to installation directory");
            return false;
        }
    }

    emit installProgress(appId, 90);

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

    if (m_registry->isProtected(appId)) {
        QString error = "Cannot uninstall protected system app";
        qWarning() << "[MarathonAppInstaller]" << error << ":" << appId;
        emit uninstallFailed(appId, error);
        return false;
    }

    if (!m_registry->hasApp(appId)) {
        emit uninstallFailed(appId, "App not found");
        return false;
    }

    QVariantMap appInfo = m_registry->getApp(appId);
    QString     appPath = appInfo.value("absolutePath").toString();

    if (appPath.isEmpty()) {
        emit uninstallFailed(appId, "App path not found");
        return false;
    }

    if (!removeDirectory(appPath)) {
        emit uninstallFailed(appId, "Failed to remove app files");
        return false;
    }

    m_scanner->scanApplications();

    emit uninstallComplete(appId);

    qDebug() << "[MarathonAppInstaller] Successfully uninstalled:" << appId;
    return true;
}
