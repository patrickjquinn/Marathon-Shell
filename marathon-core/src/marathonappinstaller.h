#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include "marathonappregistry.h"
#include "marathonappscanner.h"

class MarathonAppPackager;
class MarathonAppVerifier;
class QJsonObject;

class MarathonAppInstaller : public QObject {
    Q_OBJECT

  public:
    explicit MarathonAppInstaller(MarathonAppRegistry *registry, MarathonAppScanner *scanner,
                                  QObject *parent = nullptr);

    // An update that asks for permissions the installed version doesn't
    // have is held (installHeld) until those are in approvedPermissions.
    Q_INVOKABLE bool    installFromDirectory(const QString     &sourcePath,
                                             const QStringList &approvedPermissions = {});
    Q_INVOKABLE bool    installFromPackage(const QString     &packagePath,
                                           const QStringList &approvedPermissions = {});
    Q_INVOKABLE bool    uninstallApp(const QString &appId);
    Q_INVOKABLE bool    canUninstall(const QString &appId);
    Q_INVOKABLE QString getInstallDirectory();

  signals:
    // plan: id, name, version, signer (key id, empty if unsigned), update,
    // permissions (list of {id, label, detail, sensitive}) and added (ids
    // the installed version doesn't have).
    void installPlanned(const QString &appId, const QVariantMap &plan);
    void installHeld(const QString &appId, const QVariantMap &plan);
    void installStarted(const QString &appId);
    void installProgress(const QString &appId, int percent);
    void installComplete(const QString &appId);
    void installFailed(const QString &appId, const QString &error);
    void uninstallComplete(const QString &appId);
    void uninstallFailed(const QString &appId, const QString &error);

  private:
    bool                 validateManifest(const QString &manifestPath);
    bool place(const QJsonObject &manifest, const QString &source, const QString &signer,
               bool move);
    bool                 planInstall(const QJsonObject &manifest, const QString &signer,
                                     const QStringList &approved);
    bool                 copyDirectory(const QString &source, const QString &destination);
    bool                 removeDirectory(const QString &path);

    MarathonAppRegistry *m_registry;
    MarathonAppScanner  *m_scanner;
    MarathonAppPackager *m_packager;
    MarathonAppVerifier *m_verifier;
};
