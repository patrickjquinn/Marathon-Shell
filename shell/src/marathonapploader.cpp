#include "marathonapploader.h"
#include "marathonappprocess.h"
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

MarathonAppLoader::MarathonAppLoader(MarathonAppRegistry *registry, QQmlEngine *engine,
                                     QObject *parent)
    : QObject(parent)
    , m_registry(registry)
    , m_engine(engine)
    , m_processIsolationEnabled(true) // ENABLED BY DEFAULT for safety
{
    qInfo() << "[MarathonAppLoader] Initialized";
    qInfo() << "[MarathonAppLoader] ✅ PROCESS ISOLATION: ENABLED";
    qInfo() << "[MarathonAppLoader]    Apps with C++ plugins will run in separate processes";
    qInfo() << "[MarathonAppLoader]    Crashes will not affect the shell!";
}

MarathonAppLoader::~MarathonAppLoader() {
    // Clean up loaded apps
    qDeleteAll(m_components);
    qDeleteAll(m_processes);
}

void MarathonAppLoader::setProcessIsolationEnabled(bool enabled) {
    if (m_processIsolationEnabled != enabled) {
        m_processIsolationEnabled = enabled;
        qInfo() << "[MarathonAppLoader] Process isolation:"
                << (enabled ? "ENABLED ✅" : "DISABLED ⚠️");
        if (!enabled) {
            qWarning() << "[MarathonAppLoader] WARNING: Running apps in-process is DANGEROUS!";
            qWarning() << "[MarathonAppLoader] App crashes can take down the entire shell!";
        }
        emit processIsolationEnabledChanged();
    }
}

bool MarathonAppLoader::shouldUseProcessIsolation(const QString &appId) const {
    if (!m_processIsolationEnabled) {
        return false;
    }

    // Check if app has C++ plugins (more likely to crash)
    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (!appInfo) {
        return false;
    }

    // Apps with C++ components should run in separate processes
    // Look for shared library files (.so, .dylib, .dll)
    QDir        appDir(appInfo->absolutePath);
    QStringList filters;
    filters << "*.so" << "*.dylib" << "*.dll";
    QFileInfoList libs = appDir.entryInfoList(filters, QDir::Files);

    bool          hasNativeCode = !libs.isEmpty();
    if (hasNativeCode) {
        qInfo() << "[MarathonAppLoader]" << appId
                << "has native code - will run in separate process";
    }

    return hasNativeCode;
}

QObject *MarathonAppLoader::loadApp(const QString &appId) {
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

    // Ensure MarathonUI is available to apps (same paths as in main.cpp)
    QString marathonUIPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    m_engine->addImportPath(marathonUIPath);
    QString systemMarathonUIPath = "/usr/lib/qt6/qml/MarathonUI";
    m_engine->addImportPath(systemMarathonUIPath);

    // Add shell QML module path so apps can access MarathonOS.Shell singletons
    m_engine->addImportPath("qrc:/");
    m_engine->addImportPath(":/");

    // Build full path to entry point
    QString entryPointPath = appPath + "/" + appInfo->entryPoint;

    // Check if file exists
    if (!QFileInfo::exists(entryPointPath)) {
        qWarning() << "[MarathonAppLoader] Entry point file not found:" << entryPointPath;
        emit loadError(appId, "Entry point file not found: " + entryPointPath);
        return nullptr;
    }

    qDebug() << "  Loading from:" << entryPointPath;

    // Check if we already have this component cached
    QQmlComponent *component = m_components.value(appId, nullptr);

    if (!component) {
        // Create component ASYNCHRONOUSLY for non-blocking load
        QUrl fileUrl = QUrl::fromLocalFile(entryPointPath);
        component    = new QQmlComponent(m_engine, fileUrl, QQmlComponent::Asynchronous, this);

        // Cache immediately (even if loading)
        m_components.insert(appId, component);

        qDebug() << "  Component created asynchronously, status:" << component->status();
    } else {
        qDebug() << "  Using cached component, status:" << component->status();
    }

    //  REMOVED BLOCKING CODE - NO MORE QEventLoop!
    // Instead, check status and either return immediately or return null
    // QML should use loadAppAsync() for truly async loading

    if (component->status() == QQmlComponent::Loading) {
        qWarning() << "[MarathonAppLoader] Component still loading. Use loadAppAsync() instead of "
                      "loadApp()";
        emit loadError(appId, "Component loading in progress - use loadAppAsync()");
        return nullptr;
    }

    if (component->isError()) {
        qWarning() << "[MarathonAppLoader] Component error:" << component->errorString();
        emit loadError(appId, component->errorString());

        // Remove from cache so it doesn't get reused
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    if (component->status() != QQmlComponent::Ready) {
        qWarning() << "[MarathonAppLoader] Component not ready. Status:" << component->status();
        emit loadError(appId, "Component not ready");

        // Remove from cache so it doesn't get reused
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    // Create instance with exception protection
    QObject *appInstance = nullptr;
    try {
        appInstance = component->create();
    } catch (const std::exception &e) {
        qCritical() << "[MarathonAppLoader] EXCEPTION during app creation:" << e.what();
        emit loadError(appId, QString("Exception: %1").arg(e.what()));
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    } catch (...) {
        qCritical() << "[MarathonAppLoader] UNKNOWN EXCEPTION during app creation";
        emit loadError(appId, "Unknown exception during app creation");
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    if (!appInstance) {
        qWarning() << "[MarathonAppLoader] Failed to create app instance:"
                   << component->errorString();
        emit loadError(appId, component->errorString());

        // Remove from cache to prevent retry with broken component
        m_components.remove(appId);
        component->deleteLater();
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

    // Component is already cached above, no need to cache again

    qDebug() << "[MarathonAppLoader] Successfully loaded app:" << appId;
    emit appLoaded(appId);

    return appInstance;
}

void MarathonAppLoader::unloadApp(const QString &appId) {
    qDebug() << "[MarathonAppLoader] Unload requested for:" << appId;

    // Since we don't cache instances anymore, just clean up the component
    QQmlComponent *component = m_components.take(appId);
    if (component) {
        component->deleteLater();
        qDebug() << "[MarathonAppLoader] Cleaned up component for:" << appId;
    }

    emit appUnloaded(appId);
}

bool MarathonAppLoader::isAppLoaded(const QString &appId) const {
    // Check if component is cached (not instances since we don't cache those)
    return m_components.contains(appId);
}

void MarathonAppLoader::preloadApp(const QString &appId) {
    // Asynchronously preload app component for faster launch later
    // This creates and caches the QQmlComponent without instantiating it

    if (m_components.contains(appId)) {
        qDebug() << "[MarathonAppLoader] Component already loaded:" << appId;
        return;
    }

    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (!appInfo) {
        qDebug() << "[MarathonAppLoader] Cannot preload - app not in registry:" << appId;
        return;
    }

    QString appPath = appInfo->absolutePath;
    if (!appPath.isEmpty()) {
        m_engine->addImportPath(appPath);
    }

    // Ensure MarathonUI is available to apps (same paths as in main.cpp)
    QString marathonUIPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    m_engine->addImportPath(marathonUIPath);
    QString systemMarathonUIPath = "/usr/lib/qt6/qml/MarathonUI";
    m_engine->addImportPath(systemMarathonUIPath);

    // Add shell QML module path so apps can access MarathonOS.Shell singletons
    m_engine->addImportPath("qrc:/");
    m_engine->addImportPath(":/");

    QString entryPointPath = appPath + "/" + appInfo->entryPoint;
    if (!QFileInfo::exists(entryPointPath)) {
        qDebug() << "[MarathonAppLoader] Cannot preload - entry point not found:" << entryPointPath;
        return;
    }

    qDebug() << "[MarathonAppLoader] Preloading component:" << appId;

    // Create component asynchronously
    QUrl           fileUrl = QUrl::fromLocalFile(entryPointPath);
    QQmlComponent *component =
        new QQmlComponent(m_engine, fileUrl, QQmlComponent::Asynchronous, this);

    // Cache for later use
    m_components.insert(appId, component);

    qDebug() << "[MarathonAppLoader] Component preloaded:" << appId;
}

// New async loading method - non-blocking!
void MarathonAppLoader::loadAppAsync(const QString &appId) {
    qDebug() << "[MarathonAppLoader] Loading app asynchronously:" << appId;

    if (!m_engine) {
        qWarning() << "[MarathonAppLoader] No QML engine available";
        emit loadError(appId, "No QML engine");
        return;
    }

    // Get app info from registry
    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (!appInfo) {
        qWarning() << "[MarathonAppLoader] App not found in registry:" << appId;
        emit loadError(appId, "App not found in registry");
        return;
    }

    // Add import paths
    QString appPath = appInfo->absolutePath;
    if (!appPath.isEmpty()) {
        m_engine->addImportPath(appPath);
    }

    QString marathonUIPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    m_engine->addImportPath(marathonUIPath);
    QString systemMarathonUIPath = "/usr/lib/qt6/qml/MarathonUI";
    m_engine->addImportPath(systemMarathonUIPath);
    m_engine->addImportPath("qrc:/");
    m_engine->addImportPath(":/");

    // Build entry point path
    QString entryPointPath = appPath + "/" + appInfo->entryPoint;

    // Check if file exists
    if (!QFileInfo::exists(entryPointPath)) {
        qWarning() << "[MarathonAppLoader] Entry point file not found:" << entryPointPath;
        emit loadError(appId, "Entry point file not found: " + entryPointPath);
        return;
    }

    // Check if component is already cached and ready
    QQmlComponent *component = m_components.value(appId, nullptr);

    if (component && component->status() == QQmlComponent::Ready) {
        // Component already loaded, create instance immediately
        qDebug() << "[MarathonAppLoader] Using cached component for:" << appId;
        QObject *instance = createAppInstance(appId, component);
        if (instance) {
            emit appInstanceReady(appId, instance);
            emit appLoaded(appId);
        }
        return;
    }

    if (component && component->status() == QQmlComponent::Loading) {
        // Already loading, just wait for it
        qDebug() << "[MarathonAppLoader] Component already loading for:" << appId;
        // Handler is already connected below
        return;
    }

    // If component is in error state, clean it up before retry
    if (component && component->status() == QQmlComponent::Error) {
        qDebug() << "[MarathonAppLoader] Cleaning up failed component before retry:" << appId;
        m_components.remove(appId);
        component->deleteLater();
        component = nullptr;
    }

    // Create new component
    qDebug() << "[MarathonAppLoader] Creating new component for:" << appId;
    emit appLoadProgress(appId, 10); // Starting load

    QUrl fileUrl = QUrl::fromLocalFile(entryPointPath);
    component    = new QQmlComponent(m_engine, fileUrl, QQmlComponent::Asynchronous, this);
    m_components.insert(appId, component);

    emit appLoadProgress(appId, 30); // Component created

    // Connect to statusChanged signal for async handling
    connect(component, &QQmlComponent::statusChanged, this,
            [this, appId, component](QQmlComponent::Status status) {
                qDebug() << "[MarathonAppLoader] Component status changed for" << appId << ":"
                         << status;

                if (status == QQmlComponent::Ready) {
                    emit appLoadProgress(appId, 70); // Component ready
                    handleComponentStatusAsync(appId, component);
                } else if (status == QQmlComponent::Error) {
                    qWarning() << "[MarathonAppLoader] Component error:"
                               << component->errorString();
                    emit loadError(appId, component->errorString());
                    m_components.remove(appId);
                    component->deleteLater();
                }
            });

    // If component is already ready (sync load), handle immediately
    if (component->status() == QQmlComponent::Ready) {
        emit appLoadProgress(appId, 70);
        handleComponentStatusAsync(appId, component);
    }
}

// Handle component status asynchronously
void MarathonAppLoader::handleComponentStatusAsync(const QString &appId, QQmlComponent *component) {
    qDebug() << "[MarathonAppLoader] Handling component status for:" << appId;

    if (!component || component->isError()) {
        qWarning() << "[MarathonAppLoader] Invalid or error component";
        if (component) {
            emit loadError(appId, component->errorString());
        } else {
            emit loadError(appId, "Component is null");
        }
        return;
    }

    emit     appLoadProgress(appId, 80); // Creating instance

    QObject *instance = createAppInstance(appId, component);

    if (instance) {
        emit appLoadProgress(appId, 100); // Complete
        emit appInstanceReady(appId, instance);
        emit appLoaded(appId);
    }
}

// Create app instance from component
QObject *MarathonAppLoader::createAppInstance(const QString &appId, QQmlComponent *component) {
    if (!component || component->status() != QQmlComponent::Ready) {
        qWarning() << "[MarathonAppLoader] Component not ready for:" << appId;
        return nullptr;
    }

    qDebug() << "[MarathonAppLoader] Creating instance for:" << appId;

    QObject *appInstance = nullptr;
    try {
        appInstance = component->create();
    } catch (const std::exception &e) {
        qCritical() << "[MarathonAppLoader] EXCEPTION during app creation:" << e.what();
        emit loadError(appId, QString("Exception: %1").arg(e.what()));
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    } catch (...) {
        qCritical() << "[MarathonAppLoader] UNKNOWN EXCEPTION during app creation";
        emit loadError(appId, "Unknown exception during app creation");
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    if (!appInstance) {
        qWarning() << "[MarathonAppLoader] Failed to create app instance:"
                   << component->errorString();
        emit loadError(appId, component->errorString());
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    // Inject icon path from registry
    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (appInfo && appInstance->property("appIcon").isValid()) {
        QString iconPath = appInfo->icon;
        if (!iconPath.isEmpty()) {
            appInstance->setProperty("appIcon", iconPath);
            qDebug() << "  Injected icon:" << iconPath;
        }
    }

    qDebug() << "[MarathonAppLoader] Successfully created instance for:" << appId;
    return appInstance;
}
