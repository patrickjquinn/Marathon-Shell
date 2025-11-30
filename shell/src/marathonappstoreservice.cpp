#include "marathonappstoreservice.h"
#include "marathonappinstaller.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QNetworkRequest>
#include <QUrl>

MarathonAppStoreService::MarathonAppStoreService(MarathonAppInstaller *installer, QObject *parent)
    : QObject(parent)
    , m_installer(installer)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_catalogReply(nullptr)
    , m_catalogLoaded(false)
    , m_loading(false)
    , m_repositoryUrl("https://apps.marathonos.org/catalog.json") // Default repository
{
    qDebug() << "[MarathonAppStoreService] Initialized";

    // Load cached catalog if available
    loadCachedCatalog();
}

void MarathonAppStoreService::setRepositoryUrl(const QString &url) {
    if (m_repositoryUrl != url) {
        m_repositoryUrl = url;
        emit repositoryUrlChanged();

        // Refresh catalog with new URL
        refreshCatalog();
    }
}

QString MarathonAppStoreService::getCatalogCachePath() {
    QString cacheDir =
        QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/marathon/app-store";
    QDir dir;
    if (!dir.exists(cacheDir)) {
        dir.mkpath(cacheDir);
    }
    return cacheDir + "/catalog.json";
}

QString MarathonAppStoreService::getDownloadCachePath() {
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
        "/marathon/app-store/downloads";
    QDir dir;
    if (!dir.exists(cacheDir)) {
        dir.mkpath(cacheDir);
    }
    return cacheDir;
}

void MarathonAppStoreService::loadCachedCatalog() {
    QString cachePath = getCatalogCachePath();
    QFile   file(cachePath);

    if (!file.exists()) {
        qDebug() << "[MarathonAppStoreService] No cached catalog found";
        return;
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[MarathonAppStoreService] Failed to open cached catalog";
        return;
    }

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(file.readAll(), &error);
    file.close();

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[MarathonAppStoreService] Failed to parse cached catalog:"
                   << error.errorString();
        return;
    }

    if (doc.isArray()) {
        m_catalog       = doc.array().toVariantList();
        m_catalogLoaded = true;
        emit catalogLoadedChanged();
        qDebug() << "[MarathonAppStoreService] Loaded cached catalog with" << m_catalog.size()
                 << "apps";
    }
}

void MarathonAppStoreService::saveCatalogCache() {
    QString cachePath = getCatalogCachePath();
    QFile   file(cachePath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[MarathonAppStoreService] Failed to save catalog cache";
        return;
    }

    QJsonArray array = QJsonArray::fromVariantList(m_catalog);
    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    file.close();

    qDebug() << "[MarathonAppStoreService] Catalog cache saved";
}

void MarathonAppStoreService::refreshCatalog() {
    if (m_loading) {
        qDebug() << "[MarathonAppStoreService] Already loading catalog";
        return;
    }

    qDebug() << "[MarathonAppStoreService] Refreshing catalog from:" << m_repositoryUrl;

    m_loading = true;
    emit            loadingChanged();

    QNetworkRequest request{QUrl(m_repositoryUrl)};
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::PreferNetwork);

    m_catalogReply = m_networkManager->get(request);
    connect(m_catalogReply, &QNetworkReply::finished, this,
            &MarathonAppStoreService::handleCatalogReply);
}

void MarathonAppStoreService::handleCatalogReply() {
    m_loading = false;
    emit loadingChanged();

    if (!m_catalogReply) {
        return;
    }

    if (m_catalogReply->error() != QNetworkReply::NoError) {
        qWarning() << "[MarathonAppStoreService] Failed to fetch catalog:"
                   << m_catalogReply->errorString();
        m_catalogReply->deleteLater();
        m_catalogReply = nullptr;
        return;
    }

    QByteArray data = m_catalogReply->readAll();
    m_catalogReply->deleteLater();
    m_catalogReply = nullptr;

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[MarathonAppStoreService] Failed to parse catalog:" << error.errorString();
        return;
    }

    if (doc.isArray()) {
        m_catalog       = doc.array().toVariantList();
        m_catalogLoaded = true;
        emit catalogLoadedChanged();
        emit catalogRefreshed();

        // Save to cache
        saveCatalogCache();

        qDebug() << "[MarathonAppStoreService] Catalog loaded with" << m_catalog.size() << "apps";
    }
}

QVariantList MarathonAppStoreService::searchApps(const QString &query) {
    if (query.isEmpty()) {
        return m_catalog;
    }

    QVariantList results;
    QString      lowerQuery = query.toLower();

    for (const QVariant &item : m_catalog) {
        QVariantMap app         = item.toMap();
        QString     name        = app.value("name").toString().toLower();
        QString     description = app.value("description").toString().toLower();
        QString     id          = app.value("id").toString().toLower();

        if (name.contains(lowerQuery) || description.contains(lowerQuery) ||
            id.contains(lowerQuery)) {
            results.append(app);
        }
    }

    return results;
}

QVariantMap MarathonAppStoreService::getApp(const QString &appId) {
    for (const QVariant &item : m_catalog) {
        QVariantMap app = item.toMap();
        if (app.value("id").toString() == appId) {
            return app;
        }
    }

    return QVariantMap();
}

QVariantList MarathonAppStoreService::getFeaturedApps() {
    QVariantList featured;

    for (const QVariant &item : m_catalog) {
        QVariantMap app = item.toMap();
        if (app.value("featured").toBool()) {
            featured.append(app);
        }
    }

    // If no apps marked as featured, return first 5
    if (featured.isEmpty() && m_catalog.size() > 0) {
        for (int i = 0; i < qMin(5, m_catalog.size()); ++i) {
            featured.append(m_catalog.at(i));
        }
    }

    return featured;
}

QVariantList MarathonAppStoreService::getAppsByCategory(const QString &category) {
    QVariantList results;

    for (const QVariant &item : m_catalog) {
        QVariantMap  app        = item.toMap();
        QVariantList categories = app.value("categories").toList();

        for (const QVariant &cat : categories) {
            if (cat.toString() == category) {
                results.append(app);
                break;
            }
        }
    }

    return results;
}

void MarathonAppStoreService::downloadApp(const QString &appId) {
    QVariantMap app = getApp(appId);
    if (app.isEmpty()) {
        emit downloadFailed(appId, "App not found in catalog");
        return;
    }

    QString packageUrl = app.value("package_url").toString();
    if (packageUrl.isEmpty()) {
        emit downloadFailed(appId, "Package URL not specified");
        return;
    }

    qDebug() << "[MarathonAppStoreService] Downloading app:" << appId << "from:" << packageUrl;

    // Cancel existing download if any
    if (m_downloadReplies.contains(appId)) {
        m_downloadReplies[appId]->abort();
        m_downloadReplies[appId]->deleteLater();
        m_downloadReplies.remove(appId);
    }

    // Start download
    QNetworkRequest request{QUrl(packageUrl)};
    QNetworkReply  *reply = m_networkManager->get(request);

    // Store app ID in reply for later use
    reply->setProperty("appId", appId);

    connect(reply, &QNetworkReply::downloadProgress, this,
            &MarathonAppStoreService::handleDownloadProgress);
    connect(reply, &QNetworkReply::finished, this,
            &MarathonAppStoreService::handleDownloadFinished);

    m_downloadReplies[appId] = reply;
}

void MarathonAppStoreService::cancelDownload(const QString &appId) {
    if (m_downloadReplies.contains(appId)) {
        m_downloadReplies[appId]->abort();
        m_downloadReplies[appId]->deleteLater();
        m_downloadReplies.remove(appId);
        qDebug() << "[MarathonAppStoreService] Download cancelled:" << appId;
    }
}

void MarathonAppStoreService::handleDownloadProgress(qint64 bytesReceived, qint64 bytesTotal) {
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    QString appId = reply->property("appId").toString();
    emit    downloadProgress(appId, bytesReceived, bytesTotal);
}

void MarathonAppStoreService::handleDownloadFinished() {
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    QString appId = reply->property("appId").toString();
    m_downloadReplies.remove(appId);

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[MarathonAppStoreService] Download failed:" << appId << reply->errorString();
        emit downloadFailed(appId, reply->errorString());
        reply->deleteLater();
        return;
    }

    // Save downloaded package
    QString downloadDir = getDownloadCachePath();
    QString packagePath = downloadDir + "/" + appId + ".marathon";

    QFile   file(packagePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit downloadFailed(appId, "Failed to save package file");
        reply->deleteLater();
        return;
    }

    file.write(reply->readAll());
    file.close();
    reply->deleteLater();

    qDebug() << "[MarathonAppStoreService] Download complete:" << appId;
    emit downloadComplete(appId, packagePath);

    // Automatically trigger installation
    if (m_installer) {
        m_installer->installFromPackage(packagePath);
    }
}

QVariantList MarathonAppStoreService::getAvailableUpdates() {
    // TODO: Implement version checking against installed apps
    QVariantList updates;
    return updates;
}

void MarathonAppStoreService::checkForUpdates() {
    // Refresh catalog first
    refreshCatalog();

    // TODO: Compare catalog versions with installed apps
    // For now, just emit signal with 0 updates
    emit updatesAvailable(0);
}
