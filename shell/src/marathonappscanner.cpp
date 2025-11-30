#include "marathonappscanner.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDebug>
#ifdef HAVE_QT_CONCURRENT
#include <QtConcurrent>
#endif

MarathonAppScanner::MarathonAppScanner(MarathonAppRegistry *registry, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
#ifdef HAVE_QT_CONCURRENT
    , m_scanWatcher(new QFutureWatcher<int>(this))
#else
    , m_scanWatcher(nullptr)
#endif
{
    qDebug() << "[MarathonAppScanner] Initialized";

#ifdef HAVE_QT_CONCURRENT
    // Connect async scan completion
    connect(m_scanWatcher, &QFutureWatcher<int>::finished, this, [this]() {
        int count = m_scanWatcher->result();
        qDebug() << "[MarathonAppScanner] Async scan complete. Discovered:" << count << "apps";
        emit scanComplete(count);
    });
#endif
}

QStringList MarathonAppScanner::getSearchPaths() {
    QStringList paths;

#ifdef Q_OS_MACOS
    // macOS: use /usr/local/share (user-writable)
    paths << "/usr/local/share/marathon-apps";
#else
    // Linux: use /usr/share (system apps)
    paths << "/usr/share/marathon-apps";
#endif

    // User apps directory (works on both platforms)
    QString homeDir = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    paths << homeDir + "/.local/share/marathon-apps";

    qDebug() << "[MarathonAppScanner] Search paths:" << paths;
    return paths;
}

void MarathonAppScanner::scanApplications() {
    // Keep synchronous version for backwards compatibility
    emit scanStarted();
    int  count = performScan();
    emit scanComplete(count);
}

void MarathonAppScanner::scanApplicationsAsync() {
    qDebug() << "[MarathonAppScanner] Starting async app scan...";
    emit scanStarted();

#ifdef HAVE_QT_CONCURRENT
    // Run scan in background thread using QtConcurrent
    if (m_scanWatcher) {
        QFuture<int> future = QtConcurrent::run([this]() { return this->performScan(); });
        m_scanWatcher->setFuture(future);
    } else {
        // Fallback to synchronous if Concurrent not available
        int  count = performScan();
        emit scanComplete(count);
    }
#else
    // Fallback to synchronous if Concurrent not available
    int  count = performScan();
    emit scanComplete(count);
#endif
}

int MarathonAppScanner::performScan() {
    qDebug() << "[MarathonAppScanner] Performing app scan...";

    int         discoveredCount = 0;
    QStringList searchPaths     = getSearchPaths();

    for (const QString &searchPath : searchPaths) {
        QDir dir(searchPath);

        if (!dir.exists()) {
            qDebug() << "[MarathonAppScanner] Directory does not exist:" << searchPath;
            continue;
        }

        qDebug() << "[MarathonAppScanner] Scanning directory:" << searchPath;

        QStringList appDirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        appDirs.sort(); // Sort alphabetically for consistent ordering

        for (const QString &appDir : appDirs) {
            QString appPath      = dir.absoluteFilePath(appDir);
            QString manifestPath = appPath + "/manifest.json";

            if (!QFile::exists(manifestPath)) {
                qDebug() << "[MarathonAppScanner] No manifest found in:" << appDir;
                continue;
            }

            qDebug() << "[MarathonAppScanner] Found manifest:" << manifestPath;

            MarathonAppRegistry::AppInfo appInfo = parseManifest(manifestPath, appPath);

            if (validateManifest(appInfo)) {
                // absolutePath already set in parseManifest

                // Register with registry
                if (!m_registry->hasApp(appInfo.id)) {
                    m_registry->registerAppInfo(appInfo);
                    emit appDiscovered(appInfo.id);
                    discoveredCount++;
                } else {
                    qDebug() << "[MarathonAppScanner] App already registered:" << appInfo.id;
                }
            }
        }
    }

    qDebug() << "[MarathonAppScanner] Scan complete. Discovered:" << discoveredCount << "apps";
    return discoveredCount;
}

QString MarathonAppScanner::getManifestPath(const QString &appPath) {
    return appPath + "/manifest.json";
}

MarathonAppRegistry::AppInfo MarathonAppScanner::parseManifest(const QString &manifestPath,
                                                               const QString &appDirPath) {
    MarathonAppRegistry::AppInfo info;
    info.type         = MarathonAppRegistry::Marathon;
    info.isProtected  = false;
    info.absolutePath = appDirPath;

    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[MarathonAppScanner] Failed to open manifest:" << manifestPath;
        return info;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonParseError error;
    QJsonDocument   doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[MarathonAppScanner] JSON parse error:" << error.errorString();
        return info;
    }

    if (!doc.isObject()) {
        qWarning() << "[MarathonAppScanner] Manifest is not a JSON object";
        return info;
    }

    QJsonObject obj = doc.object();

    info.id         = obj.value("id").toString();
    info.name       = obj.value("name").toString();
    info.entryPoint = obj.value("entryPoint").toString();

    // Convert relative icon path to absolute with file:// prefix
    QString iconPath = obj.value("icon").toString();
    if (!iconPath.isEmpty() && !iconPath.startsWith("qrc:") && !iconPath.startsWith("file://")) {
        if (!iconPath.startsWith("/")) {
            // Relative path - make it absolute
            iconPath = info.absolutePath + "/" + iconPath;
        }
        // Add file:// prefix for QML Image component
        info.icon = "file://" + iconPath;
    } else {
        info.icon = iconPath;
    }

    info.version     = obj.value("version").toString("1.0.0");
    info.isProtected = obj.value("protected").toBool(false);

    // Parse permissions array
    QJsonArray permissionsArray = obj.value("permissions").toArray();
    for (const QJsonValue &value : permissionsArray) {
        info.permissions.append(value.toString());
    }

    // Parse searchKeywords array
    QJsonArray keywordsArray = obj.value("searchKeywords").toArray();
    for (const QJsonValue &value : keywordsArray) {
        info.searchKeywords.append(value.toString());
    }

    // Parse deepLinks object
    QJsonObject deepLinksObj = obj.value("deepLinks").toObject();
    info.deepLinksJson       = QJsonDocument(deepLinksObj).toJson(QJsonDocument::Compact);

    // Parse categories array
    QJsonArray categoriesArray = obj.value("categories").toArray();
    for (const QJsonValue &value : categoriesArray) {
        info.categories.append(value.toString());
    }

    // Parse handlesUriSchemes array
    QJsonArray uriSchemesArray = obj.value("handlesUriSchemes").toArray();
    for (const QJsonValue &value : uriSchemesArray) {
        info.handlesUriSchemes.append(value.toString());
    }

    // Parse defaultFor array
    QJsonArray defaultForArray = obj.value("defaultFor").toArray();
    for (const QJsonValue &value : defaultForArray) {
        info.defaultFor.append(value.toString());
    }

    qDebug() << "[MarathonAppScanner] Deep links for" << info.id << ":" << info.deepLinksJson;

    qDebug() << "[MarathonAppScanner] Parsed manifest:"
             << "ID:" << info.id << "| Name:" << info.name << "| Entry:" << info.entryPoint;

    return info;
}

bool MarathonAppScanner::validateManifest(const MarathonAppRegistry::AppInfo &info) {
    if (info.id.isEmpty()) {
        qWarning() << "[MarathonAppScanner] Invalid manifest: missing 'id'";
        return false;
    }

    if (info.name.isEmpty()) {
        qWarning() << "[MarathonAppScanner] Invalid manifest: missing 'name'";
        return false;
    }

    if (info.entryPoint.isEmpty()) {
        qWarning() << "[MarathonAppScanner] Invalid manifest: missing 'entryPoint'";
        return false;
    }

    return true;
}
