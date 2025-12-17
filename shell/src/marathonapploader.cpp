#include "marathonapploader.h"
#include "marathonappprocess.h"
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QPointer>
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
    emit          appLoadProgress(appId, 10); // Starting load

    const QString moduleUri =
        QStringLiteral("MarathonApp.%1").arg(appId.left(1).toUpper() + appId.mid(1));

    const QString componentName = QFileInfo(appInfo->entryPoint).baseName();

    qDebug() << "[MarathonAppLoader] Loading module entry point:" << moduleUri << componentName;

    component =
        new QQmlComponent(m_engine, moduleUri, componentName, QQmlComponent::Asynchronous, this);

    m_components.insert(appId, component);

    emit appLoadProgress(appId, 30); // Component created

    // Connect to statusChanged signal for async handling
    // IMPORTANT: This is async. The component may be unloaded/cancelled before it becomes Ready.
    // Use QPointer + a registry check to avoid creating instances from stale components.
    QPointer<QQmlComponent> safeComponent(component);
    connect(component, &QQmlComponent::statusChanged, this,
            [this, appId, safeComponent](QQmlComponent::Status status) {
                if (!safeComponent)
                    return;
                if (m_components.value(appId, nullptr) != safeComponent.data()) {
                    // Component was unloaded/replaced; ignore late signals.
                    qDebug() << "[MarathonAppLoader] Ignoring statusChanged for stale component:"
                             << appId;
                    return;
                }

                qDebug() << "[MarathonAppLoader] Component status changed for" << appId << ":"
                         << status;

                if (status == QQmlComponent::Ready) {
                    emit appLoadProgress(appId, 70); // Component ready
                    handleComponentStatusAsync(appId, safeComponent.data());
                } else if (status == QQmlComponent::Error) {
                    qWarning() << "[MarathonAppLoader] Component error:"
                               << safeComponent->errorString();
                    emit loadError(appId, safeComponent->errorString());
                    m_components.remove(appId);
                    safeComponent->deleteLater();
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

    // If the component was unloaded/replaced, don't proceed.
    if (m_components.value(appId, nullptr) != component) {
        qDebug()
            << "[MarathonAppLoader] Skipping handleComponentStatusAsync for unloaded component:"
            << appId;
        return;
    }

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

    // IMPORTANT:
    // Use beginCreate/completeCreate so we can set initial properties (like appIcon) BEFORE
    // Component.onCompleted runs inside the QML app. If we call component->create() and then
    // set properties afterwards, onCompleted will observe the default values (often relative
    // paths like "assets/icon.svg"), and lifecycle registration will capture the wrong icon.
    QQmlContext *ctx = component->creationContext();
    if (!ctx) {
        // Fallback: use engine root context
        ctx = m_engine ? m_engine->rootContext() : nullptr;
    }
    if (!ctx) {
        qWarning() << "[MarathonAppLoader] No QQmlContext available for app creation:" << appId;
        emit loadError(appId, "No QML context available");
        return nullptr;
    }

    QObject *appInstance = component->beginCreate(ctx);
    if (!appInstance) {
        qWarning() << "[MarathonAppLoader] beginCreate failed:" << component->errorString();
        emit loadError(appId, component->errorString());
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    // Inject icon path from registry BEFORE completeCreate (so QML sees it in onCompleted).
    MarathonAppRegistry::AppInfo *appInfo = m_registry->getAppInfo(appId);
    if (appInfo && appInstance->property("appIcon").isValid()) {
        QString iconPath = appInfo->icon;
        if (!iconPath.isEmpty()) {
            appInstance->setProperty("appIcon", iconPath);
            qDebug() << "  Injected icon:" << iconPath;
        }
    }

    component->completeCreate();
    if (component->isError()) {
        qWarning() << "[MarathonAppLoader] completeCreate error:" << component->errorString();
        emit loadError(appId, component->errorString());
        appInstance->deleteLater();
        m_components.remove(appId);
        component->deleteLater();
        return nullptr;
    }

    qDebug() << "[MarathonAppLoader] Successfully created instance for:" << appId;
    return appInstance;
}
