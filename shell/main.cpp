#include <QApplication>
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
#include <QInputDevice>
#include <QDBusMetaType>
#include "src/locationmanager.h"

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#endif

#include "src/desktopfileparser.h"
#include "src/crashhandler.h"
#include "src/appmodel.h"
#include "src/taskmodel.h"
#include "src/notificationmodel.h"
#include "src/networkmanagercpp.h"
#include "src/powermanagercpp.h"
#include "src/displaymanagercpp.h"
#include "src/audiomanagercpp.h"
#include "src/modemmanagercpp.h"
#include "src/sensormanagercpp.h"
#include "src/settingsmanager.h"
#include "src/bluetoothmanager.h"
#include "src/marathonappregistry.h"
#include "src/marathonappscanner.h"
#include "src/marathonapploader.h"
#include "src/marathonappinstaller.h"
#include "src/marathonpermissionmanager.h"
#include "src/marathonappstoreservice.h"
#include "src/contactsmanager.h"
#include "src/telephonyservice.h"
#include "src/callhistorymanager.h"
#include "src/smsservice.h"
#include "src/medialibrarymanager.h"
#include "src/musiclibrarymanager.h"
#include "src/waylandcompositormanager.h"
#include "src/marathoninputmethodengine.h"
#include "src/storagemanager.h"
#include "src/rtscheduler.h"

#include "src/mpris2controller.h"
#include "src/rotationmanager.h"
#include "src/locationmanager.h"
#include "src/hapticmanager.h"
#include "src/audioroutingmanager.h"
#include "src/securitymanager.h"
#include "src/platformcpp.h"
#include "qml/keyboard/Data/WordEngine.h"
#include "src/dbus/marathonapplicationservice.h"
#include "src/dbus/marathonsystemservice.h"
#include "src/dbus/marathonnotificationservice.h"
#include "src/dbus/freedesktopnotifications.h"
#include "src/dbus/notificationdatabase.h"
#include "src/dbus/marathonstorageservice.h"
#include "src/dbus/marathonsettingsservice.h"
#include "src/dbus/marathonpermissionportal.h"
#include <QDBusConnection>

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

#include "src/mpris_types.h"

int main(int argc, char *argv[])
{
    // Register D-Bus types needed for MPRIS2 metadata (a{sv} -> QVariantMap)
    registerMprisTypes();
    
    // Set env variables
    // Request X11 platform as we need XWayland for compatibility
    qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    
    // Force Qt to use the Linux QPA theme
    qputenv("QT_QPA_PLATFORMTHEME", "gtk3");
    
    // Use the xcb backend for input handling to avoid Wayland quirks
    // This helps with mouse and keyboard input in the embedded Wayland compositor
    qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    
    // Disable Qt Quick Compiler for better compatibility with dynamic QML
    qputenv("QML_DISABLE_DISK_CACHE", "1");
    
    // Enable software rendering for better compatibility in VMs or low-end hardware
    // qputenv("QMLSCENE_DEVICE", "software");  // Commented out - let Qt choose best renderer
    
    // Check debug mode FIRST before setting any logging rules
    QString debugEnv = qgetenv("MARATHON_DEBUG");
    bool debugEnabled = (debugEnv == "1" || debugEnv.toLower() == "true");
    
    // Configure Qt logging based on debug mode
    if (debugEnabled) {
        // Debug mode: enable OUR logs but suppress Qt internal spam
        QLoggingCategory::setFilterRules(
            // Enable all our C++ service logs by default
            "*.debug=true\n"           // Enable debug for our code
            "*.info=true\n"
            "*.warning=true\n"
            "*.error=true\n"
            // AGGRESSIVE: Suppress ALL Qt internal debug spam
            "qt.*.debug=false\n"
            "qt.*.info=false\n"
            "qt.*.warning=true\n"      // Keep Qt warnings/errors
            // CRITICAL: Enable console.log() from QML (uses QtDebugMsg)
            "qml.debug=true\n"            // Enable QML console.log()
            "js.debug=true\n"             // Enable JS console.log()
            "default.debug=true\n"        // Enable default category debug
            "default.info=true\n"
            "default.warning=true\n"
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
    
    QApplication::setApplicationName("Marathon Shell");
    QApplication::setOrganizationName("Marathon OS");
    
#ifdef HAVE_WEBENGINE
    QtWebEngineQuick::initialize();
#endif
    
    // CRITICAL: Disable Qt's automatic HiDPI scaling for the compositor window
    // 
    // Problem: On HiDPI host displays (devicePixelRatio=2), Qt automatically doubles the window's
    // internal resolution. For a 540x1140 window, Qt would render at 1080x2280 internally, then
    // downscale to fit the window, causing blurriness in embedded Wayland apps.
    //
    // Solution: Set PassThrough policy to disable automatic scaling, ensuring 1:1 pixel mapping.
    // Combined with m_output->setScaleFactor(1) in the compositor, this forces apps to render
    // at the exact window size (540x1140) without any scaling artifacts.
    //
    // Must be called BEFORE creating QApplication.
    // NOTE: We use QApplication (not QGuiApplication) to support QWidget-based components
    // like QTermWidget. QApplication inherits from QGuiApplication and adds widget support.
    QApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    
    QApplication app(argc, argv);
    
    // ============================================================================
    // CRITICAL: Install Crash Protection (MITIGATION ONLY - NOT A FIX!)
    // ============================================================================
    // This installs signal handlers to catch crashes from apps running in-process.
    // WARNING: This is a band-aid, not a solution. The PROPER fix is to run each
    // app in its own process. Signal handlers have limitations and can't always
    // prevent all crashes from taking down the shell.
    //
    // TODO: Implement multi-process app architecture (see MarathonAppLoader)
    // ============================================================================
    CrashHandler *crashHandler = CrashHandler::instance();
    crashHandler->install();
    crashHandler->setCrashCallback([](const QString& msg) {
        qCritical() << "[Marathon] App crash detected:" << msg;
        qCritical() << "[Marathon] This crash was likely caused by an app, but due to";
        qCritical() << "[Marathon] poor isolation, it's taking down the entire shell.";
    });
    qInfo() << "[Marathon] Crash protection installed (signal handlers active)";
    qInfo() << "[Marathon] ⚠ WARNING: Apps run in-process - crashes can still kill the shell";
    qInfo() << "[Marathon] ⚠ TODO: Implement proper multi-process architecture";
    
    // Set RT priority for input handling (Priority 85 per Marathon OS spec)
#ifdef Q_OS_LINUX
    struct sched_param param;
    param.sched_priority = 85;
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) == 0) {
        qInfo() << "[MarathonShell] ✓ Main thread (input handling) set to RT priority 85 (SCHED_FIFO)";
    } else {
        qWarning() << "[MarathonShell]  Failed to set RT priority for input handling";
        qInfo() << "[MarathonShell]   Configure /etc/security/limits.d/99-marathon.conf:";
        qInfo() << "[MarathonShell]     @marathon-users  -  rtprio  90";
    }
#endif
    
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
    
    // CRITICAL: Register pointer types for signal/slot marshalling across C++/QML boundary
    qRegisterMetaType<QWaylandSurface*>("QWaylandSurface*");
    qRegisterMetaType<QWaylandXdgSurface*>("QWaylandXdgSurface*");
    qRegisterMetaType<QObject*>("QObject*");
    
    qInfo() << "Wayland Compositor support enabled";
#else
    qInfo() << "Wayland Compositor support disabled (not available on this platform)";
#endif
    
    QQmlApplicationEngine engine;
    

    
    // Initialize MPRIS2 Controller (media player control)
    MPRIS2Controller *mpris2Controller = new MPRIS2Controller(&app);
    engine.rootContext()->setContextProperty("MPRIS2Controller", mpris2Controller);
    qInfo() << "[MarathonShell] ✓ MPRIS2 media controller initialized";
    
    // CRITICAL: Create SettingsManager BEFORE compositor manager
    // The compositor needs access to userScaleFactor for physical size calculation
    SettingsManager *settingsManager = new SettingsManager(&app);
    engine.rootContext()->setContextProperty("SettingsManagerCpp", settingsManager);
    
    // Register compositor manager (available on all platforms, returns null on unsupported platforms)
    // Pass SettingsManager for dynamic physical size calculation
    WaylandCompositorManager *compositorManager = new WaylandCompositorManager(settingsManager, &app);
    engine.rootContext()->setContextProperty("WaylandCompositorManager", compositorManager);
    
    // Set debug mode context property
    engine.rootContext()->setContextProperty("MARATHON_DEBUG_ENABLED", debugEnabled);
    
    // Expose Wayland availability to QML
#ifdef HAVE_WAYLAND
    engine.rootContext()->setContextProperty("HAVE_WAYLAND", true);
#else
    engine.rootContext()->setContextProperty("HAVE_WAYLAND", false);
#endif
    
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
    
    // Register Marathon Input Method Engine
    MarathonInputMethodEngine *inputMethodEngine = new MarathonInputMethodEngine(&app);
    engine.rootContext()->setContextProperty("InputMethodEngine", inputMethodEngine);
    qInfo() << "Input Method Engine initialized";
    
    // Register C++ models
    AppModel *appModel = new AppModel(&app);
    TaskModel *taskModel = new TaskModel(&app);
    NotificationModel *notificationModel = new NotificationModel(&app);
    
    // Register NotificationModel enums so they're accessible in QML
    qmlRegisterUncreatableMetaObject(
        NotificationModel::staticMetaObject,
        "MarathonOS.Shell",
        1, 0,
        "NotificationRoles",
        "Cannot create NotificationRoles enum"
    );
    
    engine.rootContext()->setContextProperty("AppModel", appModel);
    engine.rootContext()->setContextProperty("TaskModel", taskModel);
    engine.rootContext()->setContextProperty("NotificationModel", notificationModel);
    
    // Register C++ services (SettingsManager already created above for compositor)
    NetworkManagerCpp *networkManager = new NetworkManagerCpp(&app);
    PowerManagerCpp *powerManager = new PowerManagerCpp(&app);
    DisplayManagerCpp *displayManager = new DisplayManagerCpp(powerManager, &app);
    AudioManagerCpp *audioManager = new AudioManagerCpp(&app);
    ModemManagerCpp *modemManager = new ModemManagerCpp(&app);
    SensorManagerCpp *sensorManager = new SensorManagerCpp(&app);
    StorageManager *storageManager = new StorageManager(&app);
    BluetoothManager *bluetoothManager = new BluetoothManager(&app);
    RotationManager *rotationManager = new RotationManager(&app);
    LocationManager *locationManager = new LocationManager(&app);
    HapticManager *hapticManager = new HapticManager(&app);
    AudioRoutingManager *audioRoutingManager = new AudioRoutingManager(&app);
    SecurityManager *securityManager = new SecurityManager(&app);
    
    engine.rootContext()->setContextProperty("NetworkManagerCpp", networkManager);
    engine.rootContext()->setContextProperty("PowerManagerService", powerManager);
    engine.rootContext()->setContextProperty("DisplayManagerCpp", displayManager);
    engine.rootContext()->setContextProperty("AudioManagerCpp", audioManager);
    engine.rootContext()->setContextProperty("ModemManagerCpp", modemManager);
    engine.rootContext()->setContextProperty("SensorManagerCpp", sensorManager);
    engine.rootContext()->setContextProperty("StorageManager", storageManager);
    engine.rootContext()->setContextProperty("BluetoothManagerCpp", bluetoothManager);
    engine.rootContext()->setContextProperty("RotationManager", rotationManager);
    engine.rootContext()->setContextProperty("LocationManager", locationManager);
    engine.rootContext()->setContextProperty("HapticManager", hapticManager);
    engine.rootContext()->setContextProperty("AudioRoutingManagerCpp", audioRoutingManager);
    engine.rootContext()->setContextProperty("SecurityManagerCpp", securityManager);
    
    // Wire AudioManager to PowerManager for audio playback wakelocks
    QObject::connect(audioManager, &AudioManagerCpp::isPlayingChanged,
                     powerManager, [powerManager, audioManager]() {
        if (audioManager->isPlaying()) {
            powerManager->acquireWakelock("audio_playback");
            qInfo() << "[MarathonShell] Audio playback started - acquired wakelock";
        } else {
            powerManager->releaseWakelock("audio_playback");
            qInfo() << "[MarathonShell] Audio playback stopped - released wakelock";
        }
    });
    qInfo() << "[MarathonShell] ✓ Audio playback wakelock integration enabled";
    
    // Platform utilities (hardware detection, etc.)
    PlatformCpp *platformCpp = new PlatformCpp(&app);
    engine.rootContext()->setContextProperty("PlatformCpp", platformCpp);
    qInfo() << "[MarathonShell] ✓ Security Manager initialized (PAM + fprintd)";
    
    // Word Engine for spell-checking and predictions
    WordEngine *wordEngine = new WordEngine(&app);
    wordEngine->setLanguage("en_US");
    wordEngine->setEnabled(true);
    engine.rootContext()->setContextProperty("WordEngine", wordEngine);
    qInfo() << "[MarathonShell] ✓ Word Engine initialized";
    
    // Register RT Scheduler for thread priority management
    RTScheduler *rtScheduler = new RTScheduler(&app);
    engine.rootContext()->setContextProperty("RTScheduler", rtScheduler);
    if (rtScheduler->isRealtimeKernel()) {
        qInfo() << "[MarathonShell] RT Scheduler initialized (PREEMPT_RT kernel detected)";
        qInfo() << "[MarathonShell]   Current policy:" << rtScheduler->getCurrentPolicy() 
                << "Priority:" << rtScheduler->getCurrentPriority();
    }
    
    // Initialize Marathon D-Bus Services
    qInfo() << "[MarathonShell] Initializing Marathon Service Bus (D-Bus)...";
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCritical() << "[MarathonShell] Failed to connect to D-Bus session bus!";
    } else {
        qInfo() << "[MarathonShell] ✓ Connected to D-Bus session bus";
        
        // Initialize NotificationDatabase
        NotificationDatabase *notifDb = new NotificationDatabase(&app);
        if (!notifDb->initialize()) {
            qWarning() << "[MarathonShell] Failed to initialize notification database";
        }
        
        // Load existing notifications from database into model
        notificationModel->loadFromDatabase(notifDb);
        
        // Register ApplicationService
        MarathonApplicationService *appService = new MarathonApplicationService(
            appRegistry, appLoader, taskModel, &app);
        if (appService->registerService()) {
            qInfo() << "[MarathonShell]   ✓ ApplicationService registered";
        }
        
        // Register SystemService
        MarathonSystemService *systemService = new MarathonSystemService(
            powerManager, networkManager, displayManager, audioManager, &app);
        if (systemService->registerService()) {
            qInfo() << "[MarathonShell]   ✓ SystemService registered";
        }
        
        // Register NotificationService
        MarathonNotificationService *notifService = new MarathonNotificationService(notifDb, notificationModel, &app);
        if (notifService->registerService()) {
            qInfo() << "[MarathonShell]   ✓ NotificationService registered";
        }
        
        // Register freedesktop.org Notifications (standard interface for 3rd-party apps)
        FreedesktopNotifications *freedesktopNotif = new FreedesktopNotifications(notifDb, notificationModel, powerManager, &app);
        if (freedesktopNotif->registerService()) {
            qInfo() << "[MarathonShell]   ✓ org.freedesktop.Notifications registered";
        }
        
        // Expose to QML for inline-reply functionality
        engine.rootContext()->setContextProperty("FreedesktopNotifications", freedesktopNotif);
        
        // Register StorageService
        MarathonStorageService *storageService = new MarathonStorageService(storageManager, &app);
        if (storageService->registerService()) {
            qInfo() << "[MarathonShell]   ✓ StorageService registered";
        }
        
        // Register SettingsService
        MarathonSettingsService *settingsService = new MarathonSettingsService(settingsManager, &app);
        if (settingsService->registerService()) {
            qInfo() << "[MarathonShell]   ✓ SettingsService registered";
        }
        
        qInfo() << "[MarathonShell] Service bus ready (6 services active)";
    }
    
    // Register Permission Manager
    MarathonPermissionManager *permissionManager = new MarathonPermissionManager(&app);
    engine.rootContext()->setContextProperty("PermissionManager", permissionManager);
    qInfo() << "[MarathonShell] ✓ Permission Manager initialized";
    
    // Register Permission Portal (D-Bus)
    if (bus.isConnected()) {
        MarathonPermissionPortal *permissionPortal = new MarathonPermissionPortal(permissionManager, &app);
        if (permissionPortal->registerService()) {
            qInfo() << "[MarathonShell]   ✓ PermissionPortal registered";
        }
    }
    
    // Register App Store Service
    MarathonAppStoreService *appStoreService = new MarathonAppStoreService(appInstaller, &app);
    engine.rootContext()->setContextProperty("AppStoreService", appStoreService);
    qInfo() << "[MarathonShell] ✓ App Store Service initialized";
    
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
    
    // Wire AudioRoutingManager to TelephonyService for call audio routing
    QObject::connect(telephonyService, &TelephonyService::callStateChanged, 
                     audioRoutingManager, [audioRoutingManager](const QString& state) {
        if (state == "active" || state == "incoming") {
            audioRoutingManager->startCallAudio();
        } else if (state == "idle" || state == "terminated") {
            audioRoutingManager->stopCallAudio();
        }
    });
    qInfo() << "[MarathonShell] ✓ Audio routing wired to telephony";
    
    // Wire CallHistoryManager to TelephonyService for call logging
    // Track call start time and calculate duration
    static qint64 callStartTime = 0;
    static QString lastCalledNumber;
    static bool wasIncoming = false;
    
    QObject::connect(telephonyService, &TelephonyService::incomingCall, 
                     [](const QString& number) {
        callStartTime = QDateTime::currentMSecsSinceEpoch();
        lastCalledNumber = number;
        wasIncoming = true;
    });
    
    QObject::connect(telephonyService, &TelephonyService::callStateChanged, 
                     callHistoryManager, [callHistoryManager, telephonyService](const QString& state) {
        if (state == "active" && callStartTime == 0) {
            // Outgoing call started
            callStartTime = QDateTime::currentMSecsSinceEpoch();
            lastCalledNumber = telephonyService->activeNumber();
            wasIncoming = false;
        } else if (state == "idle" || state == "terminated") {
            // Call ended - calculate duration and log it
            if (callStartTime > 0 && !lastCalledNumber.isEmpty()) {
                qint64 endTime = QDateTime::currentMSecsSinceEpoch();
                int duration = (endTime - callStartTime) / 1000; // seconds
                
                QString callType;
                if (wasIncoming) {
                    // If duration > 0, call was answered, otherwise it was missed
                    callType = (duration > 0) ? "incoming" : "missed";
                } else {
                    callType = "outgoing";
                }
                
                callHistoryManager->addCall(lastCalledNumber, callType, callStartTime, duration);
                qInfo() << "[MarathonShell] ✓ Call logged:" << callType << lastCalledNumber << duration << "s";
                
                // Reset tracking
                callStartTime = 0;
                lastCalledNumber.clear();
                wasIncoming = false;
            }
        }
    });
    qInfo() << "[MarathonShell] ✓ Call history wired to telephony";
    
    // Register Media Library services
    MediaLibraryManager *mediaLibraryManager = new MediaLibraryManager(&app);
    MusicLibraryManager *musicLibraryManager = new MusicLibraryManager(&app);
    
    engine.rootContext()->setContextProperty("MediaLibraryManager", mediaLibraryManager);
    engine.rootContext()->setContextProperty("MusicLibraryManager", musicLibraryManager);
    
    // Note: org.freedesktop.Notifications is handled by FreedesktopNotifications (line 367)
    // Note: org.marathon.NotificationService is handled by MarathonNotificationService (line 361)
    // Legacy NotificationService removed to avoid DBus path conflict
    
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
    
    // Use the mobile-friendly filter setting
    bool filterMobile = settingsManager->filterMobileFriendlyApps();
    qDebug() << "[Marathon] Filter mobile-friendly apps:" << filterMobile;
    
    QVariantList nativeApps = desktopFileParser->scanApplications(searchPaths, filterMobile);
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
    
    // ============================================================================
    // CRITICAL: MarathonUI QML Module Import Paths
    // 
    // MarathonUI is a separate QML module library that must be built and either:
    // 1. Installed to a known location, OR
    // 2. Found in the build directory (for development without install)
    //
    // Qt searches for QML modules in paths added via engine.addImportPath().
    // For a module URI like "MarathonUI.Theme", Qt looks for:
    //   <importPath>/MarathonUI/Theme/qmldir
    // ============================================================================
    
    // Priority 1: User-local installation (recommended for development)
    // This is where `cmake --install .` installs to by default (without sudo)
    QString userMarathonUIPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    engine.addImportPath(userMarathonUIPath);
    qDebug() << "[QML Import] User-local MarathonUI:" << userMarathonUIPath;
    
    // Priority 2: System-wide installation (production deployments)
    // This is where system packages would install MarathonUI
    QString systemMarathonUIPath = "/usr/lib/qt6/qml";  // Parent of MarathonUI/
    engine.addImportPath(systemMarathonUIPath);
    qDebug() << "[QML Import] System-wide Qt modules:" << systemMarathonUIPath;
    
    // Priority 3: Build directory (for development without install)
    // When running from build dir, MarathonUI modules are in build/MarathonUI/
    // QCoreApplication::applicationDirPath() = <project>/build/shell
    // So ../MarathonUI = <project>/build/MarathonUI (WRONG - this doesn't exist!)
    // Correct path: ../ = <project>/build (contains MarathonUI/ subdirectory)
    QString buildMarathonUIPath = QCoreApplication::applicationDirPath() + "/..";
    engine.addImportPath(buildMarathonUIPath);
    qDebug() << "[QML Import] Build directory:" << buildMarathonUIPath;
    
    // Verify MarathonUI.Theme is loadable (most critical dependency)
    QDir themeCheck1(userMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck2(systemMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck3(buildMarathonUIPath + "/MarathonUI/Theme");
    
    bool marathonUIFound = themeCheck1.exists() || themeCheck2.exists() || themeCheck3.exists();
    
    if (!marathonUIFound) {
        qCritical() << "";
        qCritical() << "========================================================================";
        qCritical() << " FATAL: MarathonUI QML modules not found!";
        qCritical() << "========================================================================";
        qCritical() << "";
        qCritical() << "MarathonUI must be built and installed before running Marathon Shell.";
        qCritical() << "";
        qCritical() << "QUICK FIX:";
        qCritical() << "  cd" << QDir::current().absolutePath();
        qCritical() << "  ./scripts/build-all.sh";
        qCritical() << "";
        qCritical() << "MANUAL BUILD (if build-all.sh fails):";
        qCritical() << "  cd" << QDir::current().absolutePath();
        qCritical() << "  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release";
        qCritical() << "  cmake --build build -j$(nproc)";
        qCritical() << "  cmake --install build  # Installs to ~/.local/share/marathon-ui";
        qCritical() << "";
        qCritical() << "CHECKED PATHS:";
        qCritical() << "  1." << themeCheck1.absolutePath() << (themeCheck1.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  2." << themeCheck2.absolutePath() << (themeCheck2.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  3." << themeCheck3.absolutePath() << (themeCheck3.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "";
        qCritical() << "========================================================================";
        qCritical() << "";
        
        // Don't exit immediately - let QML engine fail with detailed error
        // This helps users see which specific module import failed
    } else {
        qInfo() << "[MarathonShell] ✓ MarathonUI modules found";
        if (themeCheck1.exists()) qDebug() << "  - Using user-local installation";
        else if (themeCheck2.exists()) qDebug() << "  - Using system-wide installation";
        else if (themeCheck3.exists()) qDebug() << "  - Using build directory (development mode)";
    }
    
    // Qt 6.5+ uses ':/qt/qml/' as the default resource prefix for QML modules
    const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));
    
    // Register custom D-Bus types
    qRegisterMetaType<GeoClueTimestamp>("GeoClueTimestamp");
    qDBusRegisterMetaType<GeoClueTimestamp>();

    // Debug: List input devices to diagnose touchscreen issues
    const auto devices = QInputDevice::devices();
    qInfo() << "[MarathonShell] Detected Input Devices:";
    for (const QInputDevice *device : devices) {
        qInfo() << "  -" << device->name() 
                << "Type:" << device->type() 
                << "ID:" << device->systemId()
                << "Seat:" << device->seatName();
    }
    
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

