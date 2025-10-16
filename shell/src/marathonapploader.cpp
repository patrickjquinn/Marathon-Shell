#include "marathonapploader.h"
#include <QDebug>
#include <QFileInfo>

MarathonAppLoader::MarathonAppLoader(MarathonAppRegistry *registry, QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
    , m_engine(engine)
{
    qDebug() << "[MarathonAppLoader] Initialized";
}

MarathonAppLoader::~MarathonAppLoader()
{
    // Clean up loaded apps
    qDeleteAll(m_components);
}

QObject* MarathonAppLoader::loadApp(const QString &appId)
{
    if (!m_engine) {
        qWarning() << "[MarathonAppLoader] No QML engine available";
        emit loadError(appId, "No QML engine");
        return nullptr;
    }
    
    // Don't cache - create fresh instance each time
    // QML objects can only have one parent, so reusing breaks when switching apps
    qDebug() << "[MarathonAppLoader] Creating new instance for:" << appId;
    
    // Get app info from registry
    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (!appInfo) {
        qWarning() << "[MarathonAppLoader] App not found in registry:" << appId;
        emit loadError(appId, "App not found in registry");
        return nullptr;
    }
    
    qDebug() << "[MarathonAppLoader] Loading app:" << appId;
    qDebug() << "  Path:" << appInfo->absolutePath;
    qDebug() << "  Entry:" << appInfo->entryPoint;
    
    // Add app path to import paths so it can find its own components
    QString appPath = appInfo->absolutePath;
    if (!appPath.isEmpty()) {
        m_engine->addImportPath(appPath);
        qDebug() << "  Added import path:" << appPath;
    }
    
    // Build full path to entry point
    QString entryPointPath = appPath + "/" + appInfo->entryPoint;
    
    // Check if file exists
    if (!QFileInfo::exists(entryPointPath)) {
        qWarning() << "[MarathonAppLoader] Entry point file not found:" << entryPointPath;
        emit loadError(appId, "Entry point file not found: " + entryPointPath);
        return nullptr;
    }
    
    qDebug() << "  Loading from:" << entryPointPath;
    
    // Create component
    QQmlComponent *component = new QQmlComponent(m_engine, QUrl::fromLocalFile(entryPointPath), this);
    
    if (component->isLoading()) {
        qDebug() << "  Component is loading asynchronously...";
    }
    
    if (component->isError()) {
        qWarning() << "[MarathonAppLoader] Component error:" << component->errorString();
        emit loadError(appId, component->errorString());
        delete component;
        return nullptr;
    }
    
    if (component->status() != QQmlComponent::Ready) {
        qWarning() << "[MarathonAppLoader] Component not ready. Status:" << component->status();
        emit loadError(appId, "Component not ready");
        delete component;
        return nullptr;
    }
    
    // Create instance
    QObject *appInstance = component->create();
    
    if (!appInstance) {
        qWarning() << "[MarathonAppLoader] Failed to create app instance:" << component->errorString();
        emit loadError(appId, component->errorString());
        delete component;
        return nullptr;
    }
    
    // Inject icon path from registry into the app instance
    // This ensures task switcher shows the correct icon
    if (appInstance->property("appIcon").isValid()) {
        QString iconPath = appInfo->icon;
        if (!iconPath.isEmpty()) {
            appInstance->setProperty("appIcon", iconPath);
            qDebug() << "  Injected icon:" << iconPath;
        }
    }
    
    // Don't cache instances - each launch gets a fresh instance
    // Component can be reused though
    if (!m_components.contains(appId)) {
        m_components.insert(appId, component);
    } else {
        delete component; // Already have this component cached
    }
    
    qDebug() << "[MarathonAppLoader] Successfully loaded app:" << appId;
    emit appLoaded(appId);
    
    return appInstance;
}

void MarathonAppLoader::unloadApp(const QString &appId)
{
    qDebug() << "[MarathonAppLoader] Unload requested for:" << appId;
    
    // Since we don't cache instances anymore, just clean up the component
    QQmlComponent *component = m_components.take(appId);
    if (component) {
        component->deleteLater();
        qDebug() << "[MarathonAppLoader] Cleaned up component for:" << appId;
    }
    
    emit appUnloaded(appId);
}

bool MarathonAppLoader::isAppLoaded(const QString &appId) const
{
    // Check if component is cached (not instances since we don't cache those)
    return m_components.contains(appId);
}

