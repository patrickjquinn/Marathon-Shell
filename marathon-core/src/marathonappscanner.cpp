#include "marathonappscanner.h"
#include "marathonapppaths.h"
#include "marathonappverifier.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <utility> // std::as_const
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

    connect(m_scanWatcher, &QFutureWatcher<int>::finished, this, [this]() {
        int count = m_scanWatcher->result();
        qDebug() << "[MarathonAppScanner] Async scan complete. Discovered:" << count << "apps";
        emit scanComplete(count);
    });
#endif
}

MarathonAppRegistry::AppInfo MarathonAppScanner::systemApp(const QString &appId) {
    const QString                dir  = MarathonAppPaths::systemApps() + QLatin1Char('/') + appId;
    MarathonAppRegistry::AppInfo info = parseManifest(getManifestPath(dir), dir);
    info.isSystem                     = true;
    return info;
}

// A user install counts only with the installer's receipt, whose
// permissions are the ones the user approved; the manifest beside the
// code is not trusted for them.
MarathonAppRegistry::AppInfo MarathonAppScanner::userApp(const QString &appId) {
    QFile             file(MarathonAppPaths::receiptPath(appId));
    const QJsonObject receipt = file.open(QIODevice::ReadOnly) ?
        QJsonDocument::fromJson(file.readAll()).object() :
        QJsonObject();
    if (receipt.value("id").toString() != appId) {
        qWarning() << "[MarathonAppScanner] No install receipt for" << appId;
        return {};
    }
    const QString                dir  = MarathonAppPaths::filesDir(appId);
    MarathonAppRegistry::AppInfo info = parseManifest(getManifestPath(dir), dir);
    if (info.id != appId)
        return {};
    info.permissions.clear();
    const QJsonArray granted = receipt.value("permissions").toArray();
    for (const auto &value : granted)
        info.permissions.append(value.toString());
    info.isSystem    = MarathonAppVerifier::isSystemSigner(receipt.value("signer").toString());
    info.isProtected = info.isProtected && info.isSystem;
    return info;
}

bool MarathonAppScanner::registerFound(const MarathonAppRegistry::AppInfo &info) {
    if (!validateManifest(info) || m_registry->hasApp(info.id))
        return false;
    m_registry->registerAppInfo(info);
    emit appDiscovered(info.id);
    return true;
}

void MarathonAppScanner::scanApplications() {

    emit scanStarted();
    int  count = performScan();
    emit scanComplete(count);
}

bool MarathonAppScanner::scanSingleApp(const QString &appId) {
    if (appId.isEmpty() || !m_registry)
        return false;

    const bool system =
        QFile::exists(getManifestPath(MarathonAppPaths::systemApps() + QLatin1Char('/') + appId));
    const MarathonAppRegistry::AppInfo info = system ? systemApp(appId) : userApp(appId);
    if (!validateManifest(info) || info.id != appId)
        return false;
    m_registry->registerAppInfo(info);
    return true;
}

void MarathonAppScanner::scanApplicationsAsync() {
    qDebug() << "[MarathonAppScanner] Starting async app scan...";
    emit scanStarted();

#ifdef HAVE_QT_CONCURRENT

    if (m_scanWatcher) {
        QFuture<int> future = QtConcurrent::run([this]() { return this->performScan(); });
        m_scanWatcher->setFuture(future);
    } else {

        int  count = performScan();
        emit scanComplete(count);
    }
#else

    int  count = performScan();
    emit scanComplete(count);
#endif
}

int MarathonAppScanner::performScan() {
    int         discoveredCount = 0;

    QStringList system =
        QDir(MarathonAppPaths::systemApps()).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    system.sort();
    for (const QString &appId : std::as_const(system)) {
        if (QFile::exists(getManifestPath(MarathonAppPaths::systemApps() + '/' + appId)))
            discoveredCount += registerFound(systemApp(appId)) ? 1 : 0;
    }

    QStringList installed =
        QDir(MarathonAppPaths::userInstalls()).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    installed.sort();
    for (const QString &appId : std::as_const(installed))
        discoveredCount += registerFound(userApp(appId)) ? 1 : 0;

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

    QString iconPath = obj.value("icon").toString();
    if (!iconPath.isEmpty() && !iconPath.startsWith("qrc:") && !iconPath.startsWith("file://")) {
        if (!iconPath.startsWith("/")) {

            iconPath = info.absolutePath + "/" + iconPath;
        }

        info.icon = "file://" + iconPath;
    } else {
        info.icon = iconPath;
    }

    info.version     = obj.value("version").toString("1.0.0");
    info.isProtected = obj.value("protected").toBool(false);

    QJsonArray permissionsArray = obj.value("permissions").toArray();
    for (const auto &value : std::as_const(permissionsArray)) {
        info.permissions.append(value.toString());
    }

    QJsonArray keywordsArray = obj.value("searchKeywords").toArray();
    for (const auto &value : std::as_const(keywordsArray)) {
        info.searchKeywords.append(value.toString());
    }

    QJsonObject deepLinksObj = obj.value("deepLinks").toObject();
    info.deepLinksJson       = QJsonDocument(deepLinksObj).toJson(QJsonDocument::Compact);

    QJsonArray categoriesArray = obj.value("categories").toArray();
    for (const auto &value : std::as_const(categoriesArray)) {
        info.categories.append(value.toString());
    }

    QJsonArray uriSchemesArray = obj.value("handlesUriSchemes").toArray();
    for (const auto &value : std::as_const(uriSchemesArray)) {
        info.handlesUriSchemes.append(value.toString());
    }

    QJsonArray defaultForArray = obj.value("defaultFor").toArray();
    for (const auto &value : std::as_const(defaultForArray)) {
        info.defaultFor.append(value.toString());
    }

    QJsonArray bgCapArray = obj.value("backgroundCapabilities").toArray();
    for (const auto &value : std::as_const(bgCapArray)) {
        info.backgroundCapabilities.append(value.toString());
    }

    QJsonArray qtModulesArray = obj.value("requiresQtModules").toArray();
    for (const auto &value : std::as_const(qtModulesArray)) {
        info.requiresQtModules.append(value.toString());
    }
    info.toolkit = obj.value("toolkit").toString(QStringLiteral("keel"));

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
