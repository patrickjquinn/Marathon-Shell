#include "marathonapppackager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>

MarathonAppPackager::MarathonAppPackager(QObject *parent)
    : QObject(parent) {}

bool MarathonAppPackager::validateAppDirectory(const QString &appDir) {
    QDir dir(appDir);
    if (!dir.exists()) {
        m_lastError = "App directory does not exist: " + appDir;
        return false;
    }

    // Check for manifest.json
    QString manifestPath = appDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "manifest.json not found in app directory";
        return false;
    }

    // Validate manifest
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

    QJsonObject obj = doc.object();

    // Check required fields
    QStringList requiredFields = {"id", "name", "version", "entryPoint", "icon"};
    for (const QString &field : requiredFields) {
        if (!obj.contains(field) || obj.value(field).toString().isEmpty()) {
            m_lastError = "manifest.json missing required field: " + field;
            return false;
        }
    }

    // Check if entryPoint exists
    QString entryPoint = obj.value("entryPoint").toString();
    if (!QFile::exists(appDir + "/" + entryPoint)) {
        m_lastError = "Entry point file not found: " + entryPoint;
        return false;
    }

    return true;
}

bool MarathonAppPackager::createZipArchive(const QString &sourceDir, const QString &zipPath) {
    // Use zip command for creating archive
    QProcess zipProcess;

    // Change to source directory and create zip
    QStringList args;
    args << "-r" << zipPath << ".";

    zipProcess.setWorkingDirectory(sourceDir);
    zipProcess.start("zip", args);

    if (!zipProcess.waitForStarted()) {
        m_lastError = "Failed to start zip process";
        return false;
    }

    if (!zipProcess.waitForFinished(30000)) { // 30 second timeout
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
    // Ensure destination exists
    QDir dir;
    if (!dir.mkpath(destDir)) {
        m_lastError = "Failed to create destination directory: " + destDir;
        return false;
    }

    // Use unzip command for extraction
    QProcess    unzipProcess;

    QStringList args;
    args << "-o" << zipPath << "-d" << destDir;

    unzipProcess.start("unzip", args);

    if (!unzipProcess.waitForStarted()) {
        m_lastError = "Failed to start unzip process";
        return false;
    }

    if (!unzipProcess.waitForFinished(30000)) { // 30 second timeout
        m_lastError = "Unzip process timed out";
        return false;
    }

    if (unzipProcess.exitCode() != 0) {
        QString errorMsg = QString::fromUtf8(unzipProcess.readAllStandardError());
        // unzip returns 1 for warnings, which is often ok
        if (unzipProcess.exitCode() > 1) {
            m_lastError = "Unzip process failed: " + errorMsg;
            return false;
        }
    }

    return true;
}

bool MarathonAppPackager::verifyPackageStructure(const QString &extractedDir) {
    // Verify manifest.json exists
    QString manifestPath = extractedDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "Extracted package missing manifest.json";
        return false;
    }

    // Validate manifest
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

    return true;
}

bool MarathonAppPackager::createPackage(const QString &appDir, const QString &outputPath) {
    qDebug() << "[MarathonAppPackager] Creating package from:" << appDir;
    qDebug() << "[MarathonAppPackager] Output path:" << outputPath;

    emit packagingProgress(10);

    // Validate app directory
    if (!validateAppDirectory(appDir)) {
        qWarning() << "[MarathonAppPackager] Validation failed:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit packagingProgress(30);

    // Remove output file if it exists
    if (QFile::exists(outputPath)) {
        if (!QFile::remove(outputPath)) {
            m_lastError = "Failed to remove existing output file: " + outputPath;
            emit error(m_lastError);
            return false;
        }
    }

    emit packagingProgress(50);

    // Create zip archive
    if (!createZipArchive(appDir, outputPath)) {
        qWarning() << "[MarathonAppPackager] Failed to create zip:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit packagingProgress(90);

    // Verify the created package
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

    // Check if package exists
    if (!QFile::exists(packagePath)) {
        m_lastError = "Package file does not exist: " + packagePath;
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(30);

    // Create temporary directory for extraction
    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        m_lastError = "Failed to create temporary directory";
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(50);

    // Extract to temp directory first
    QString tempExtractPath = tempDir.path();
    if (!extractZipArchive(packagePath, tempExtractPath)) {
        qWarning() << "[MarathonAppPackager] Extraction failed:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(70);

    // Verify package structure
    if (!verifyPackageStructure(tempExtractPath)) {
        qWarning() << "[MarathonAppPackager] Package structure invalid:" << m_lastError;
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(85);

    // Move to final destination
    QDir destDirObj(destDir);
    if (destDirObj.exists()) {
        if (!destDirObj.removeRecursively()) {
            m_lastError = "Failed to remove existing destination directory";
            emit error(m_lastError);
            return false;
        }
    }

    // Create parent directory
    QDir parentDir = QFileInfo(destDir).dir();
    if (!parentDir.mkpath(QFileInfo(destDir).fileName())) {
        m_lastError = "Failed to create destination directory";
        emit error(m_lastError);
        return false;
    }

    // Rename temp directory to destination
    if (!QDir().rename(tempExtractPath, destDir)) {
        m_lastError = "Failed to move extracted files to destination";
        emit error(m_lastError);
        return false;
    }

    emit extractionProgress(100);

    qDebug() << "[MarathonAppPackager] Package extracted successfully";
    return true;
}
