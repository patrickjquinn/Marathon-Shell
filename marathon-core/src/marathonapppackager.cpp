#include "marathonapppackager.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include "marathon-core-native/src/lib.rs.h"
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
    const QByteArray   source  = sourceDir.toUtf8();
    const QByteArray   archive = zipPath.toUtf8();
    const rust::String failure =
        marathon::native::create_package_archive(rust::Str(source.constData(), source.size()),
                                                 rust::Str(archive.constData(), archive.size()));
    if (failure.empty())
        return true;
    m_lastError = "Failed to create package: " + QString::fromUtf8(failure.data(), failure.size());
    return false;
}

bool MarathonAppPackager::extractZipArchive(const QString &zipPath, const QString &destDir) {
    const QByteArray   archive = zipPath.toUtf8();
    const QByteArray   dest    = destDir.toUtf8();
    const rust::String failure = marathon::native::extract_package_archive(
        rust::Str(archive.constData(), archive.size()), rust::Str(dest.constData(), dest.size()));
    if (failure.empty())
        return true;
    const QString reason = QString::fromUtf8(failure.data(), failure.size());
    m_lastError          = "Failed to extract package: " + reason;
    qWarning() << "[MarathonAppPackager] SECURITY:" << m_lastError;
    syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Package refused: %s: %s", archive.constData(),
           reason.toUtf8().constData());
    return false;
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
    // Parsed only to validate the manifest -- the document itself is not
    // needed here, only `error`.
    (void)QJsonDocument::fromJson(manifestFile.readAll(), &error);
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
