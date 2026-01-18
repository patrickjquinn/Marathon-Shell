#pragma once

#include <QObject>
#include <QString>

class MarathonAppPackager : public QObject {
    Q_OBJECT

  public:
    explicit MarathonAppPackager(QObject *parent = nullptr);

    Q_INVOKABLE bool    createPackage(const QString &appDir, const QString &outputPath);

    Q_INVOKABLE bool    extractPackage(const QString &packagePath, const QString &destDir);

    Q_INVOKABLE QString lastError() const {
        return m_lastError;
    }

  signals:
    void packagingProgress(int percent);
    void extractionProgress(int percent);
    void error(const QString &message);

  private:
    bool    validateAppDirectory(const QString &appDir);
    bool    createZipArchive(const QString &sourceDir, const QString &zipPath);
    bool    extractZipArchive(const QString &zipPath, const QString &destDir);
    bool    verifyPackageStructure(const QString &extractedDir);
    bool    verifyNoSymlinkEscape(const QString &dir, const QString &baseDir);

    QString m_lastError;
};
