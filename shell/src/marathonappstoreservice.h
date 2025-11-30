#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class MarathonAppInstaller;

class MarathonAppStoreService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool catalogLoaded READ catalogLoaded NOTIFY catalogLoadedChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(
        QString repositoryUrl READ repositoryUrl WRITE setRepositoryUrl NOTIFY repositoryUrlChanged)

  public:
    explicit MarathonAppStoreService(MarathonAppInstaller *installer, QObject *parent = nullptr);

    // Properties
    bool catalogLoaded() const {
        return m_catalogLoaded;
    }
    bool loading() const {
        return m_loading;
    }
    QString repositoryUrl() const {
        return m_repositoryUrl;
    }
    void setRepositoryUrl(const QString &url);

    // Catalog operations
    Q_INVOKABLE void         refreshCatalog();
    Q_INVOKABLE QVariantList searchApps(const QString &query = QString());
    Q_INVOKABLE QVariantMap  getApp(const QString &appId);
    Q_INVOKABLE QVariantList getFeaturedApps();
    Q_INVOKABLE QVariantList getAppsByCategory(const QString &category);

    // Download and install
    Q_INVOKABLE void downloadApp(const QString &appId);
    Q_INVOKABLE void cancelDownload(const QString &appId);

    // Updates
    Q_INVOKABLE QVariantList getAvailableUpdates();
    Q_INVOKABLE void         checkForUpdates();

  signals:
    void catalogLoadedChanged();
    void loadingChanged();
    void repositoryUrlChanged();
    void catalogRefreshed();
    void downloadProgress(const QString &appId, qint64 bytesReceived, qint64 bytesTotal);
    void downloadComplete(const QString &appId, const QString &packagePath);
    void downloadFailed(const QString &appId, const QString &error);
    void updatesAvailable(int count);

  private slots:
    void handleCatalogReply();
    void handleDownloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    void handleDownloadFinished();

  private:
    void                           loadCachedCatalog();
    void                           saveCatalogCache();
    QString                        getCatalogCachePath();
    QString                        getDownloadCachePath();

    MarathonAppInstaller          *m_installer;
    QNetworkAccessManager         *m_networkManager;
    QNetworkReply                 *m_catalogReply;
    QMap<QString, QNetworkReply *> m_downloadReplies;

    bool                           m_catalogLoaded;
    bool                           m_loading;
    QString                        m_repositoryUrl;
    QVariantList                   m_catalog;
};
