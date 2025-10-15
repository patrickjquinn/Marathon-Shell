#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QDebug>
#include <QQmlContext>
#include <QDir>

#include "src/desktopfileparser.h"
#include "src/appmodel.h"
#include "src/taskmodel.h"
#include "src/notificationmodel.h"
#include "src/networkmanagercpp.h"
#include "src/powermanagercpp.h"
#include "src/notificationservice.h"
#include "src/settingsmanager.h"
#include "src/bluetoothmanager.h"
#include "src/marathonappregistry.h"
#include "src/marathonappscanner.h"
#include "src/marathonapploader.h"
#include "src/marathonappinstaller.h"

#ifdef HAVE_WAYLAND
#include "src/waylandcompositor.h"
#endif

int main(int argc, char *argv[])
{
    QGuiApplication::setApplicationName("Marathon Shell");
    QGuiApplication::setOrganizationName("Marathon OS");
    
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Basic");
    
#ifdef HAVE_WAYLAND
    qmlRegisterType<WaylandCompositor>("MarathonOS.Wayland", 1, 0, "WaylandCompositor");
    qDebug() << "Wayland Compositor support enabled";
#else
    qDebug() << "Wayland Compositor support disabled (not available on this platform)";
#endif
    
    QQmlApplicationEngine engine;
    
    // Register DesktopFileParser as a singleton accessible from QML
    DesktopFileParser *desktopFileParser = new DesktopFileParser(&app);
    engine.rootContext()->setContextProperty("DesktopFileParserCpp", desktopFileParser);
    
    // Register Marathon App System
    MarathonAppRegistry *appRegistry = new MarathonAppRegistry(&app);
    MarathonAppScanner *appScanner = new MarathonAppScanner(appRegistry, &app);
    MarathonAppLoader *appLoader = new MarathonAppLoader(appRegistry, &engine, &app);
    MarathonAppInstaller *appInstaller = new MarathonAppInstaller(appRegistry, appScanner, &app);
    
    engine.rootContext()->setContextProperty("MarathonAppRegistry", appRegistry);
    engine.rootContext()->setContextProperty("MarathonAppScanner", appScanner);
    engine.rootContext()->setContextProperty("MarathonAppLoader", appLoader);
    engine.rootContext()->setContextProperty("MarathonAppInstaller", appInstaller);
    
    // Register C++ models
    AppModel *appModel = new AppModel(&app);
    TaskModel *taskModel = new TaskModel(&app);
    NotificationModel *notificationModel = new NotificationModel(&app);
    
    engine.rootContext()->setContextProperty("AppModel", appModel);
    engine.rootContext()->setContextProperty("TaskModel", taskModel);
    engine.rootContext()->setContextProperty("NotificationModel", notificationModel);
    
    // Register C++ services
    NetworkManagerCpp *networkManager = new NetworkManagerCpp(&app);
    PowerManagerCpp *powerManager = new PowerManagerCpp(&app);
    SettingsManager *settingsManager = new SettingsManager(&app);
    BluetoothManager *bluetoothManager = new BluetoothManager(&app);
    
    engine.rootContext()->setContextProperty("NetworkManagerCpp", networkManager);
    engine.rootContext()->setContextProperty("PowerManagerCpp", powerManager);
    engine.rootContext()->setContextProperty("SettingsManagerCpp", settingsManager);
    engine.rootContext()->setContextProperty("BluetoothManagerCpp", bluetoothManager);
    
    // Register notification service (D-Bus daemon)
    NotificationService *notificationService = new NotificationService(notificationModel, &app);
    bool notificationServiceRegistered = notificationService->registerService();
    if (notificationServiceRegistered) {
        qDebug() << "Notification service registered successfully";
    } else {
        qDebug() << "Failed to register notification service (may already be running)";
    }
    
    // Note: Marathon apps are auto-initialized in AppModel constructor
    
    // Scan for native apps and add to AppModel
    QStringList searchPaths = {"/usr/share/applications", "/usr/local/share/applications", 
                               QDir::homePath() + "/.local/share/applications"};
    QVariantList nativeApps = desktopFileParser->scanApplications(searchPaths);
    for (const QVariant& appVariant : nativeApps) {
        QVariantMap app = appVariant.toMap();
        appModel->addApp(app["id"].toString(), app["name"].toString(), 
                       app["icon"].toString(), app["type"].toString());
    }
    
    // Scan for Marathon apps
    qDebug() << "Scanning for Marathon apps...";
    appScanner->scanApplications();
    
    // Load apps from registry into AppModel
    appModel->loadFromRegistry(appRegistry);
    
    // Add QML import paths for modules
    engine.addImportPath("qrc:/");
    engine.addImportPath(":/");
    
    // Add build directory path for MarathonUI modules
    QString buildPath = QCoreApplication::applicationDirPath() + "/../../../qml";
    engine.addImportPath(buildPath);
    qDebug() << "Added QML import path:" << buildPath;
    
    const QUrl url(QStringLiteral("qrc:/MarathonOS/Shell/qml/Main.qml"));
    
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML";
                QCoreApplication::exit(-1);
            }
        }, Qt::QueuedConnection);
    
    engine.load(url);
    
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }
    
    qDebug() << "Marathon OS Shell started";
    return app.exec();
}

