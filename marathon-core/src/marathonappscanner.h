#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#ifdef HAVE_QT_CONCURRENT
#include <QFutureWatcher>
#endif
#include "marathonappregistry.h"

class MarathonAppScanner : public QObject {
    Q_OBJECT

  public:
    explicit MarathonAppScanner(MarathonAppRegistry *registry, QObject *parent = nullptr);

    Q_INVOKABLE void    scanApplications();
    Q_INVOKABLE void    scanApplicationsAsync();
    Q_INVOKABLE QString getManifestPath(const QString &appPath);

  signals:
    void scanStarted();
    void appDiscovered(const QString &appId);
    void scanProgress(int current, int total);
    void scanComplete(int count);
    void scanError(const QString &error);

  private:
    QStringList                  getSearchPaths();
    MarathonAppRegistry::AppInfo parseManifest(const QString &manifestPath,
                                               const QString &appDirPath);
    bool                         validateManifest(const MarathonAppRegistry::AppInfo &info);
    int                          performScan();

    MarathonAppRegistry         *m_registry;
#ifdef HAVE_QT_CONCURRENT
    QFutureWatcher<int> *m_scanWatcher;
#else
    void *m_scanWatcher;
#endif
};
