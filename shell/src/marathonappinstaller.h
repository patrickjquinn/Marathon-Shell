#pragma once

#include <QObject>
#include <QString>
#include "marathonappregistry.h"
#include "marathonappscanner.h"

class MarathonAppPackager;
class MarathonAppVerifier;

class MarathonAppInstaller : public QObject {
    Q_OBJECT

  public:
    explicit MarathonAppInstaller(MarathonAppRegistry *registry, MarathonAppScanner *scanner,
                                  QObject *parent = nullptr);

    Q_INVOKABLE bool    installFromDirectory(const QString &sourcePath);
    Q_INVOKABLE bool    installFromPackage(const QString &packagePath);
    Q_INVOKABLE bool    uninstallApp(const QString &appId);
    Q_INVOKABLE bool    canUninstall(const QString &appId);
    Q_INVOKABLE QString getInstallDirectory();

  signals:
    void installStarted(const QString &appId);
    void installProgress(const QString &appId, int percent);
    void installComplete(const QString &appId);
    void installFailed(const QString &appId, const QString &error);
    void uninstallComplete(const QString &appId);
    void uninstallFailed(const QString &appId, const QString &error);

  private:
    QString              getTargetInstallPath();
    bool                 validateManifest(const QString &manifestPath);
    bool                 copyDirectory(const QString &source, const QString &destination);
    bool                 removeDirectory(const QString &path);

    MarathonAppRegistry *m_registry;
    MarathonAppScanner  *m_scanner;
    MarathonAppPackager *m_packager;
    MarathonAppVerifier *m_verifier;
};
