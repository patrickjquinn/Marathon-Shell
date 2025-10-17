#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include "marathonappregistry.h"

class MarathonAppScanner : public QObject {
    Q_OBJECT
    
public:
    explicit MarathonAppScanner(MarathonAppRegistry *registry, QObject *parent = nullptr);
    
    Q_INVOKABLE void scanApplications();
    Q_INVOKABLE QString getManifestPath(const QString &appPath);
    
signals:
    void scanStarted();
    void appDiscovered(const QString &appId);
    void scanComplete(int count);
    void scanError(const QString &error);
    
private:
    QStringList getSearchPaths();
    MarathonAppRegistry::AppInfo parseManifest(const QString &manifestPath, const QString &appDirPath);
    bool validateManifest(const MarathonAppRegistry::AppInfo &info);
    
    MarathonAppRegistry *m_registry;
};

