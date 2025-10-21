#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QDebug>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QStandardPaths>
#include <QLoggingCategory>

#include "src/desktopfileparser.h"
#include "src/appmodel.h"
#include "src/taskmodel.h"
#include "src/notificationmodel.h"
#include "src/networkmanagercpp.h"
#include "src/powermanagercpp.h"
#include "src/displaymanagercpp.h"
#include "src/audiomanagercpp.h"
#include "src/modemmanagercpp.h"
#include "src/sensormanagercpp.h"
#include "src/notificationservice.h"
#include "src/settingsmanager.h"
#include "src/bluetoothmanager.h"
#include "src/marathonappregistry.h"
#include "src/marathonappscanner.h"
#include "src/marathonapploader.h"
#include "src/marathonappinstaller.h"
#include "src/contactsmanager.h"
#include "src/telephonyservice.h"
#include "src/callhistorymanager.h"
#include "src/smsservice.h"
#include "src/medialibrarymanager.h"
#include "src/musiclibrarymanager.h"
#include "src/waylandcompositormanager.h"

#ifdef HAVE_WAYLAND
#include "src/waylandcompositor.h"
#include <QWaylandSurface>
#include <QWaylandXdgShell>
#endif

#ifdef HAVE_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

// Custom message handler for logging Qt messages
static QFile *logFile = nullptr;
static void marathonMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    // Only suppress truly harmless warnings (not in debug mode)
    QString debugEnv = qgetenv("MARATHON_DEBUG");
    bool debugMode = (debugEnv == "1" || debugEnv.toLower() == "true");
    
    if (!debugMode && type == QtWarningMsg) {
        // In non-debug mode, suppress known benign warnings
        if ((msg.contains("Could not connect") && 
             (msg.contains("NetworkManager") || msg.contains("UPower"))) ||
            msg.contains("Failed to initialize EGL display")) {
            return;
        }
    }
    
    QString logLevel;
    switch (type) {
    case QtDebugMsg:
        logLevel = "DEBUG";
        break;
    case QtInfoMsg:
        logLevel = "INFO";
        break;
    case QtWarningMsg:
        logLevel = "WARNING";
        break;
    case QtCriticalMsg:
        logLevel = "CRITICAL";
        break;
    case QtFatalMsg:
        logLevel = "FATAL";
        break;
    }
    
    QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
    QString logMessage = QString("[%1] [%2] %3").arg(timestamp, logLevel, msg);
    
    if (context.file) {
        logMessage += QString(" (%1:%2)").arg(context.file).arg(context.line);
    }
    
    // Write to file
    if (logFile && logFile->isOpen()) {
        QTextStream stream(logFile);
        stream << logMessage << "\n";
        stream.flush();
    }
    
    // ALWAYS output to stderr for terminal visibility
    fprintf(stderr, "%s\n", qPrintable(logMessage));
    
    // For fatal errors, close log file before abort
    if (type == QtFatalMsg) {
        if (logFile) {
            logFile->close();
            delete logFile;
            logFile = nullptr;
        }
        abort();
    }
}

int main(int argc, char *argv[])
{
    // Check debug mode FIRST before setting any logging rules
    QString debugEnv = qgetenv("MARATHON_DEBUG");
    bool debugEnabled = (debugEnv == "1" || debugEnv.toLower() == "true");
    
    // Configure Qt logging based on debug mode
    if (debugEnabled) {
        // Debug mode: enable OUR logs but suppress Qt internal spam
        QLoggingCategory::setFilterRules(
            "*.debug=false\n"           // Disable debug by default (too spammy)
            "*.info=true\n"
            "*.warning=true\n"
            "*.error=true\n"
            // Suppress Qt internal spam
            "qt.qpa.*=false\n"
            "qt.pointer.*=false\n"
            "qt.quick.*=false\n"
            "qt.scenegraph.*=false\n"
            "qt.qml.connections=false\n"  // Suppress only QML connections spam
            "qt.qml.binding=false\n"      // Suppress only QML binding spam
            "qt.core.*=false\n"
            "qt.rhi.*=false\n"            // Disable RHI (rendering) spam
            "qml=true\n"                  // ENABLE console.log() from QML
            "default.info=true\n"
            "default.warning=true\n"
            "js.info=true\n"
        );
    } else {
        // Production mode: filter out noisy categories
        QLoggingCategory::setFilterRules(
            "*.debug=false\n"
            "*.info=false\n"
            "*.warning=true\n"
            "*.error=true\n"
            "qt.qpa.*=false\n"
            "qt.pointer.*=false\n"
            "qt.quick.*=false\n"
            "qt.scenegraph.*=false\n"
            "marathon.*.info=true\n"
        );
    }
    
    QGuiApplication::setApplicationName("Marathon Shell");
    QGuiApplication::setOrganizationName("Marathon OS");
    
#ifdef HAVE_WEBENGINE
    QtWebEngineQuick::initialize();
#endif
    
    QGuiApplication app(argc, argv);
    
    // Initialize logging
    QString logPath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + "/.marathon";
    QDir logDir(logPath);
    if (!logDir.exists()) {
        logDir.mkpath(".");
    }
    
    logFile = new QFile(logPath + "/crash.log");
    if (logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        qInstallMessageHandler(marathonMessageHandler);
        qInfo() << "Marathon Shell starting...";
        qInfo() << "Log file:" << logFile->fileName();
    } else {
        qWarning() << "Failed to open log file:" << logFile->fileName();
        delete logFile;
        logFile = nullptr;
    }
    
    QQuickStyle::setStyle("Basic");
    
    // Debug mode was already checked at the start
    if (debugEnabled) {
        qDebug() << "Debug mode enabled via MARATHON_DEBUG";
    }
    
#ifdef HAVE_WAYLAND
    // Register types needed for signal marshalling to QML
    qmlRegisterUncreatableType<QWaylandSurface>("MarathonOS.Wayland", 1, 0, "WaylandSurface",
                                                  "WaylandSurface cannot be created from QML");
    qmlRegisterUncreatableType<QWaylandXdgSurface>("MarathonOS.Wayland", 1, 0, "WaylandXdgSurface",
                                                     "WaylandXdgSurface cannot be created from QML");
    qmlRegisterUncreatableType<WaylandCompositor>("MarathonOS.Wayland", 1, 0, "WaylandCompositor",
                                                    "WaylandCompositor is created in C++");
    qInfo() << "Wayland Compositor support enabled";
#else
    qInfo() << "Wayland Compositor support disabled (not available on this platform)";
#endif
    
    QQmlApplicationEngine engine;
    
    // Register compositor manager (available on all platforms, returns null on unsupported platforms)
    WaylandCompositorManager *compositorManager = new WaylandCompositorManager(&app);
    engine.rootContext()->setContextProperty("WaylandCompositorManager", compositorManager);
    
    // Set debug mode context property
    engine.rootContext()->setContextProperty("MARATHON_DEBUG_ENABLED", debugEnabled);
    
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
    DisplayManagerCpp *displayManager = new DisplayManagerCpp(&app);
    AudioManagerCpp *audioManager = new AudioManagerCpp(&app);
    ModemManagerCpp *modemManager = new ModemManagerCpp(&app);
    SensorManagerCpp *sensorManager = new SensorManagerCpp(&app);
    SettingsManager *settingsManager = new SettingsManager(&app);
    BluetoothManager *bluetoothManager = new BluetoothManager(&app);
    
    engine.rootContext()->setContextProperty("NetworkManagerCpp", networkManager);
    engine.rootContext()->setContextProperty("PowerManagerCpp", powerManager);
    engine.rootContext()->setContextProperty("DisplayManagerCpp", displayManager);
    engine.rootContext()->setContextProperty("AudioManagerCpp", audioManager);
    engine.rootContext()->setContextProperty("ModemManagerCpp", modemManager);
    engine.rootContext()->setContextProperty("SensorManagerCpp", sensorManager);
    engine.rootContext()->setContextProperty("SettingsManagerCpp", settingsManager);
    engine.rootContext()->setContextProperty("BluetoothManagerCpp", bluetoothManager);
    
    // Register Telephony & Messaging services
    ContactsManager *contactsManager = new ContactsManager(&app);
    TelephonyService *telephonyService = new TelephonyService(&app);
    CallHistoryManager *callHistoryManager = new CallHistoryManager(&app);
    SMSService *smsService = new SMSService(&app);
    
    // Wire up contacts to call history for name resolution
    callHistoryManager->setContactsManager(contactsManager);
    smsService->setContactsManager(contactsManager);
    
    engine.rootContext()->setContextProperty("ContactsManager", contactsManager);
    engine.rootContext()->setContextProperty("TelephonyService", telephonyService);
    engine.rootContext()->setContextProperty("CallHistoryManager", callHistoryManager);
    engine.rootContext()->setContextProperty("SMSService", smsService);
    
    // Register Media Library services
    MediaLibraryManager *mediaLibraryManager = new MediaLibraryManager(&app);
    MusicLibraryManager *musicLibraryManager = new MusicLibraryManager(&app);
    
    engine.rootContext()->setContextProperty("MediaLibraryManager", mediaLibraryManager);
    engine.rootContext()->setContextProperty("MusicLibraryManager", musicLibraryManager);
    
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
    QStringList searchPaths = {
        "/usr/share/applications",
        "/usr/local/share/applications",
        QDir::homePath() + "/.local/share/applications",
        "/var/lib/flatpak/exports/share/applications",  // System Flatpak apps
        QDir::homePath() + "/.local/share/flatpak/exports/share/applications"  // User Flatpak apps
    };
    qDebug() << "[Marathon] Scanning for native apps in:" << searchPaths;
    QVariantList nativeApps = desktopFileParser->scanApplications(searchPaths);
    qDebug() << "[Marathon] Found" << nativeApps.count() << "native apps";
    for (const QVariant& appVariant : nativeApps) {
        QVariantMap app = appVariant.toMap();
        appModel->addApp(app["id"].toString(), app["name"].toString(), 
                       app["icon"].toString(), app["type"].toString(), app["exec"].toString());
        qDebug() << "[Marathon] Added app:" << app["name"].toString() 
                 << "(" << app["id"].toString() << ") exec:" << app["exec"].toString();
    }
    
    // Scan for Marathon apps
    qDebug() << "Scanning for Marathon apps...";
    appScanner->scanApplications();
    
    // Load apps from registry into AppModel
    appModel->loadFromRegistry(appRegistry);
    
    // Sort all apps alphabetically after loading both native and Marathon apps
    appModel->sortAppsByName();
    
    // Add QML import paths for modules
    engine.addImportPath("qrc:/");
    engine.addImportPath(":/");
    
    // Add build directory path for MarathonUI modules (for development)
    QString buildPath = QCoreApplication::applicationDirPath() + "/../../../qml";
    engine.addImportPath(buildPath);
    qDebug() << "Added QML import path:" << buildPath;
    
    // MarathonUI plugin modules are built in qml/MarathonUI/*/qml/
    QString marathonUIContainersPath = QCoreApplication::applicationDirPath() + "/../../../qml/MarathonUI/Containers/qml";
    engine.addImportPath(marathonUIContainersPath);
    qDebug() << "Added MarathonUI.Containers import path:" << marathonUIContainersPath;
    
    QString marathonUICorePath = QCoreApplication::applicationDirPath() + "/../../../qml/MarathonUI/Core/qml";
    engine.addImportPath(marathonUICorePath);
    qDebug() << "Added MarathonUI.Core import path:" << marathonUICorePath;
    
    QString marathonUIControlsPath = QCoreApplication::applicationDirPath() + "/../../../qml/MarathonUI/Controls/qml";
    engine.addImportPath(marathonUIControlsPath);
    qDebug() << "Added MarathonUI.Controls import path:" << marathonUIControlsPath;
    
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

