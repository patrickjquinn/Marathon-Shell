#include "marathonapppackager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <syslog.h>

static bool copyDirRecursively(const QString &sourceDir, const QString &destDir) {
    QDir src(sourceDir);
    if (!src.exists()) {
        return false;
    }

    QDir dst(destDir);
    if (!dst.exists()) {
        if (!dst.mkpath(".")) {
            return false;
        }
    }

    const QFileInfoList entries = src.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);
    for (const QFileInfo &entry : entries) {
        const QString srcPath = entry.absoluteFilePath();
        const QString dstPath = destDir + "/" + entry.fileName();

        if (entry.isDir()) {
            if (!copyDirRecursively(srcPath, dstPath)) {
                return false;
            }
        } else {
            if (QFile::exists(dstPath)) {
                QFile::remove(dstPath);
            }
            if (!QFile::copy(srcPath, dstPath)) {
                return false;
            }
        }
    }
    return true;
}

MarathonAppPackager::MarathonAppPackager(QObject *parent)
    : QObject(parent) {}

bool MarathonAppPackager::verifyNoSymlinkEscape(const QString &dir, const QString &baseDir) {
    QDir                directory(dir);
    QString             canonicalBase = QFileInfo(baseDir).canonicalFilePath();

    const QFileInfoList entries =
        directory.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::System);

    for (const QFileInfo &entry : entries) {
        if (entry.isSymLink()) {
            QString   target = entry.symLinkTarget();
            QFileInfo targetInfo(target);
            QString   canonicalTarget = targetInfo.canonicalFilePath();

            if (canonicalTarget.isEmpty()) {
                canonicalTarget =
                    QFileInfo(entry.absolutePath() + "/" + target).canonicalFilePath();
            }

            if (!canonicalTarget.startsWith(canonicalBase + "/") &&
                canonicalTarget != canonicalBase) {
                m_lastError = QString("Symlink escape detected: %1 -> %2")
                                  .arg(entry.absoluteFilePath(), target);
                qWarning() << "[MarathonAppPackager] SECURITY:" << m_lastError;
                syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Symlink escape in package: %s -> %s",
                       entry.absoluteFilePath().toUtf8().constData(), target.toUtf8().constData());
                return false;
            }
        } else if (entry.isDir()) {
            if (!verifyNoSymlinkEscape(entry.absoluteFilePath(), baseDir)) {
                return false;
            }
        }
    }
    return true;
}

bool MarathonAppPackager::validateAppDirectory(const QString &appDir) {
    QDir dir(appDir);
    if (!dir.exists()) {
        m_lastError = "App directory does not exist: " + appDir;
        return false;
    }

    QString manifestPath = appDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "manifest.json not found in app directory";
        return false;
    }

    QFile manifestFile(manifestPath);
    if (!manifestFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = "Failed to open manifest.json";
        return false;
    }

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(manifestFile.readAll(), &error);
    manifestFile.close();

    if (error.error != QJsonParseError::NoError) {
        m_lastError = "Invalid JSON in manifest.json: " + error.errorString();
        return false;
    }

    if (!doc.isObject()) {
        m_lastError = "manifest.json must be a JSON object";
        return false;
    }

    QJsonObject obj            = doc.object();
    QStringList requiredFields = {"id", "name", "version", "entryPoint", "icon"};

    for (const QString &field : requiredFields) {
        if (!obj.contains(field) || obj.value(field).toString().isEmpty()) {
            m_lastError = "manifest.json missing required field: " + field;
            return false;
        }
    }

    QString entryPoint = obj.value("entryPoint").toString();
    if (!QFile::exists(appDir + "/" + entryPoint)) {
        m_lastError = "Entry point file not found: " + entryPoint;
        return false;
    }

    return true;
}

bool MarathonAppPackager::createZipArchive(const QString &sourceDir, const QString &zipPath) {
    QProcess    zipProcess;
    QStringList args;
    args << "-r" << zipPath << ".";

    zipProcess.setWorkingDirectory(sourceDir);
    zipProcess.start("zip", args);

    if (!zipProcess.waitForStarted()) {
        m_lastError = "Failed to start zip process";
        return false;
    }

    if (!zipProcess.waitForFinished(30000)) {
        m_lastError = "Zip process timed out";
        return false;
    }

    if (zipProcess.exitCode() != 0) {
        m_lastError = "Zip process failed: " + QString::fromUtf8(zipProcess.readAllStandardError());
        return false;
    }

    return true;
}

bool MarathonAppPackager::extractZipArchive(const QString &zipPath, const QString &destDir) {
    QDir dir;
    if (!dir.mkpath(destDir)) {
        m_lastError = "Failed to create destination directory: " + destDir;
        return false;
    }

    QProcess    unzipProcess;
    QStringList args;
    args << "-o" << zipPath << "-d" << destDir;

    unzipProcess.start("unzip", args);

    if (!unzipProcess.waitForStarted()) {
        m_lastError = "Failed to start unzip process";
        return false;
    }

    if (!unzipProcess.waitForFinished(30000)) {
        m_lastError = "Unzip process timed out";
        return false;
    }

    if (unzipProcess.exitCode() > 1) {
        m_lastError =
            "Unzip process failed: " + QString::fromUtf8(unzipProcess.readAllStandardError());
        return false;
    }

    return true;
}

bool MarathonAppPackager::verifyPackageStructure(const QString &extractedDir) {
    QString manifestPath = extractedDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "Extracted package missing manifest.json";
        return false;
    }

    QFile manifestFile(manifestPath);
    if (!manifestFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = "Failed to read manifest.json from package";
        return false;
    }

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(manifestFile.readAll(), &error);
    manifestFile.close();

    if (error.error != QJsonParseError::NoError) {
        m_lastError = "Invalid manifest.json in package: " + error.errorString();
        return false;
    }

    if (!verifyNoSymlinkEscape(extractedDir, extractedDir)) {
        return false;
    }

    return true;
}

bool MarathonAppPackager::createPackage(const QString &appDir, const QString &outputPath) {
    qDebug() << "[MarathonAppPackager] Creating package from:" << appDir;
    qDebug() << "[MarathonAppPackager] Output path:" << outputPath;

    emit packagingProgress(10);

    if (!validateAppDirectory(appDir)) {
        qWarning() << "[MarathonAppPackager] Validation failed:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit packagingProgress(30);

    if (QFile::exists(outputPath)) {
        if (!QFile::remove(outputPath)) {
            m_lastError = "Failed to remove existing output file: " + outputPath;
            emit error(m_lastError);
            return false;
        }
    }

    emit packagingProgress(50);

    if (!createZipArchive(appDir, outputPath)) {
        qWarning() << "[MarathonAppPackager] Failed to create zip:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit packagingProgress(90);

    if (!QFile::exists(outputPath)) {
        m_lastError = "Package file was not created: " + outputPath;
        emit error(m_lastError);
        return false;
    }

    emit packagingProgress(100);

    qDebug() << "[MarathonAppPackager] Package created successfully:" << outputPath;
    return true;
}

bool MarathonAppPackager::extractPackage(const QString &packagePath, const QString &destDir) {
    qDebug() << "[MarathonAppPackager] Extracting package:" << packagePath;
    qDebug() << "[MarathonAppPackager] Destination:" << destDir;

    emit extractionProgress(10);

    if (!QFile::exists(packagePath)) {
        m_lastError = "Package file does not exist: " + packagePath;
        emit error(m_lastError);
        return false;
    }

    emit          extractionProgress(30);

    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        m_lastError = "Failed to create temporary directory";
        emit error(m_lastError);
        return false;
    }

    emit    extractionProgress(50);

    QString tempExtractPath = tempDir.path();
    if (!extractZipArchive(packagePath, tempExtractPath)) {
        qWarning() << "[MarathonAppPackager] Extraction failed:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(70);

    if (!verifyPackageStructure(tempExtractPath)) {
        qWarning() << "[MarathonAppPackager] Package structure invalid:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(85);

    QDir destDirObj(destDir);
    if (destDirObj.exists()) {
        if (!destDirObj.removeRecursively()) {
            m_lastError = "Failed to remove existing destination directory";
            emit error(m_lastError);
            return false;
        }
    }

    QDir parentDir = QFileInfo(destDir).dir();
    if (!parentDir.exists() && !parentDir.mkpath(".")) {
        m_lastError = "Failed to create destination parent directory";
        emit error(m_lastError);
        return false;
    }

    if (!QDir().rename(tempExtractPath, destDir)) {
        if (!copyDirRecursively(tempExtractPath, destDir)) {
            m_lastError = "Failed to move extracted files to destination";
            emit error(m_lastError);
            return false;
        }
    }

    emit extractionProgress(100);

    qDebug() << "[MarathonAppPackager] Package extracted successfully";
    return true;
}
