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
#include <QElapsedTimer>

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#endif

#include "src/components/desktopfileparser.h"
#include "src/components/crashhandler.h"
#include "src/models/appmodel.h"
#include "src/models/taskmodel.h"
#include "src/managers/alarmmanagercpp.h"
#include "src/services/applaunchservice.h"
#include "src/services/applifecyclemanager.h"
#include "src/models/notificationmodel.h"
#include "src/services/notificationhandlercpp.h"
#include "src/services/notificationservicecpp.h"
#include "src/managers/networkmanagercpp.h"
#include "src/managers/powermanagercpp.h"
#include "src/controllers/powerpolicycontroller.h"
#include "src/managers/displaymanagercpp.h"
#include "src/controllers/displaypolicycontroller.h"
#include "src/services/powerbatteryhandlercpp.h"
#include "src/managers/audiomanagercpp.h"
#include "src/managers/modemmanagercpp.h"
#include "src/managers/sensormanagercpp.h"
#include "src/managers/settingsmanager.h"
#include "src/managers/bluetoothmanager.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"
#include "marathonappinstaller.h"
#include "src/marathonpermissionmanager.h"
#include "src/services/marathonappstoreservice.h"
#include "contactsmanager.h"
#include "telephonyservice.h"
#include "callhistorymanager.h"
#include "smsservice.h"
#include "medialibrarymanager.h"
#include "musiclibrarymanager.h"
#include "src/wayland/waylandcompositormanager.h"
#include "src/managers/marathoninputmethodengine.h"
#include "src/managers/rtscheduler.h"
#include "src/managers/cursormanager.h"
#include "src/components/lunasvgimageprovider.h"

#include "src/managers/mpris2controller.h"
#include "src/managers/rotationmanager.h"
#include "src/managers/locationmanager.h"
#include "src/managers/clipboardmanagercpp.h"
#include "src/managers/hapticmanager.h"
#include "src/managers/flashlightmanagercpp.h"
#include "src/controllers/audioroutingmanager.h"
#include "src/controllers/audiopolicycontroller.h"
#include "src/managers/securitymanager.h"
#include "src/managers/screenmetrics.h"
#include "src/managers/platformcpp.h"
#include "src/services/navigationroutercpp.h"
#include "src/services/statusbariconservicecpp.h"
#include "src/services/statemanagercpp.h"
#include "src/services/unifiedsearchservicecpp.h"
#include "src/services/telephonyintegrationcpp.h"
#include "src/services/screenshotservicecpp.h"
#include "src/services/sessionstore.h"
#include "src/services/systemstatusstore.h"
#include "src/services/systemcontrolstore.h"
#include "src/services/uistore.h"
#include "src/services/appstore.h"
#include "src/services/wallpaperstore.h"
#include "src/services/router.h"
#include "src/services/surfaceregistry.h"
#include "src/services/languagemanager.h"
#include "src/services/dictionary.h"
#include "src/services/autocorrect.h"
#include "src/services/emojipredictor.h"
#include "src/services/phrasepredictor.h"
#include "src/services/inputcontext.h"
#include "qml/keyboard/Data/WordEngine.h"
#include "src/dbus/freedesktopnotifications.h"
#include "src/dbus/notificationdatabase.h"
#include "src/ipc/shellipcserver.h"
#include <QDBusConnection>

#ifdef HAVE_WAYLAND
#include "src/wayland/waylandcompositor.h"
#include <QWaylandSurface>
#include <QWaylandXdgShell>
#endif

#ifdef HAVE_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

template <typename T, typename... Args>
static T *createObject(QQmlContext *ctx, const char *qmlName, Args &&...args) {
    static_assert(std::is_base_of_v<QObject, T>, "T must inherit QObject");

    T *obj = new T(std::forward<Args>(args)...);
    ctx->setContextProperty(qmlName, obj);
    return obj;
}

static QFile       *logFile   = nullptr;
static QTextStream *logStream = nullptr;
static QMutex       logMutex;
static bool         g_debugEnabled = false;
static void         marathonMessageHandler(QtMsgType type, const QMessageLogContext &context,
                                           const QString &msg) {

    QMutexLocker locker(&logMutex);

    if (!g_debugEnabled && type == QtWarningMsg) {

        if ((msg.contains("Could not connect") &&
             (msg.contains("NetworkManager") || msg.contains("UPower"))) ||

            msg.contains("libEGL warning: failed to get driver name for fd -1") ||
            msg.contains("MESA-LOADER: failed to retrieve device information") ||
            msg.contains("Failed to initialize EGL display")) {
            return;
        }
    }

    QString logLevel;
    switch (type) {
        case QtDebugMsg: logLevel = "DEBUG"; break;
        case QtInfoMsg: logLevel = "INFO"; break;
        case QtWarningMsg: logLevel = "WARNING"; break;
        case QtCriticalMsg: logLevel = "CRITICAL"; break;
        case QtFatalMsg: logLevel = "FATAL"; break;
    }

    QString timestamp  = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
    QString logMessage = QString("[%1] [%2] %3").arg(timestamp, logLevel, msg);

    if (context.file) {
        logMessage += QString(" (%1:%2)").arg(context.file).arg(context.line);
    }

    if (logStream && logFile && logFile->isOpen()) {
        (*logStream) << logMessage << "\n";

        if (g_debugEnabled || type >= QtWarningMsg) {
            logStream->flush();
        }
    }

    if (g_debugEnabled || type >= QtWarningMsg) {
        fprintf(stderr, "%s\n", qPrintable(logMessage));
    }

    if (type == QtFatalMsg) {
        if (logFile) {
            if (logStream) {
                logStream->flush();
                delete logStream;
                logStream = nullptr;
            }
            logFile->close();
            delete logFile;
            logFile = nullptr;
        }
        abort();
    }
}

#include "src/components/mpris_types.h"

int main(int argc, char *argv[]) {

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");

    registerMprisTypes();

    QString debugEnv     = qgetenv("MARATHON_DEBUG");
    bool    debugEnabled = (debugEnv == "1" || debugEnv.toLower() == "true");
    g_debugEnabled       = debugEnabled;

    QElapsedTimer timer;
    timer.start();
    if (debugEnabled) {
        qDebug() << "[Profiler] Startup begins...";
    }

    const QString profileEnv  = qgetenv("MARATHON_PROFILE");
    const bool    profileMode = (profileEnv == "1" || profileEnv.toLower() == "true");
    if (debugEnabled) {

        QString rules =

            QStringLiteral("*.debug=true\n") + QStringLiteral("*.info=true\n") +
            QStringLiteral("*.warning=true\n") + QStringLiteral("*.error=true\n")

            + QStringLiteral("qt.*.debug=false\n") + QStringLiteral("qt.*.info=false\n") +
            QStringLiteral("qt.*.warning=true\n")

            + QStringLiteral("qml.debug=true\n") + QStringLiteral("js.debug=true\n") +
            QStringLiteral("default.debug=true\n") + QStringLiteral("default.info=true\n") +
            QStringLiteral("default.warning=true\n");

        if (profileMode) {
            rules += QStringLiteral("qt.scenegraph.time.*=true\n");
            rules += QStringLiteral("qt.scenegraph.time.renderloop=true\n");
        }
        QLoggingCategory::setFilterRules(rules);
    } else {

        QString rules = QStringLiteral("*.debug=false\n") + QStringLiteral("*.info=false\n") +
            QStringLiteral("*.warning=true\n") + QStringLiteral("*.error=true\n") +
            QStringLiteral("qt.qpa.*=false\n") + QStringLiteral("qt.pointer.*=false\n") +
            QStringLiteral("qt.quick.*=false\n") + QStringLiteral("qt.scenegraph.*=false\n") +
            QStringLiteral("marathon.*.info=true\n");
        if (profileMode) {
            rules += QStringLiteral("qt.scenegraph.time.*=true\n");
            rules += QStringLiteral("qt.scenegraph.time.renderloop=true\n");
        }
        QLoggingCategory::setFilterRules(rules);
    }

    QApplication::setApplicationName("Marathon Shell");
    QApplication::setOrganizationName("Marathon OS");

#ifdef HAVE_WEBENGINE
    QtWebEngineQuick::initialize();
#endif

    QApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents);

    QApplication  app(argc, argv);

    CrashHandler *crashHandler = CrashHandler::instance();
    crashHandler->install();
    crashHandler->setCrashCallback([](const QString &msg) {
        qCritical() << "[Marathon] App crash detected:" << msg;
        qCritical() << "[Marathon] Crash occurred in the shell process.";
    });
    qInfo() << "[Marathon] Crash protection installed (signal handlers active)";

#ifdef Q_OS_LINUX
    struct sched_param param;
    param.sched_priority = 85;
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) == 0) {
        qInfo()
            << "[MarathonShell] ✓ Main thread (input handling) set to RT priority 85 (SCHED_FIFO)";
    } else {
        qWarning() << "[MarathonShell]  Failed to set RT priority for input handling";
        qInfo() << "[MarathonShell]   Configure /etc/security/limits.d/99-marathon.conf:";
        qInfo() << "[MarathonShell]     @marathon-users  -  rtprio  90";
    }
#endif

    QString logPath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + "/.marathon";
    QDir    logDir(logPath);
    if (!logDir.exists()) {
        logDir.mkpath(".");
    }

    logFile = new QFile(logPath + "/crash.log");
    if (logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        logStream = new QTextStream(logFile);
        qInstallMessageHandler(marathonMessageHandler);
        qInfo() << "Marathon Shell starting...";
        qInfo() << "Log file:" << logFile->fileName();
    } else {
        qWarning() << "Failed to open log file:" << logFile->fileName();
        delete logFile;
        logFile = nullptr;
    }
    if (debugEnabled) {
        qDebug() << "[Profiler] Logging initialized:" << timer.elapsed() << "ms";
    }

    QQuickStyle::setStyle("Basic");

    if (debugEnabled) {
        qDebug() << "Debug mode enabled via MARATHON_DEBUG";
    }

#ifdef HAVE_WAYLAND

    qmlRegisterUncreatableType<QWaylandSurface>("MarathonOS.Wayland", 1, 0, "WaylandSurface",
                                                "WaylandSurface cannot be created from QML");
    qmlRegisterUncreatableType<QWaylandXdgSurface>("MarathonOS.Wayland", 1, 0, "WaylandXdgSurface",
                                                   "WaylandXdgSurface cannot be created from QML");
    qmlRegisterUncreatableType<WaylandCompositor>("MarathonOS.Wayland", 1, 0, "WaylandCompositor",
                                                  "WaylandCompositor is created in C++");

    qRegisterMetaType<QWaylandSurface *>("QWaylandSurface*");
    qRegisterMetaType<QWaylandXdgSurface *>("QWaylandXdgSurface*");
    qRegisterMetaType<QObject *>("QObject*");

    qInfo() << "Wayland Compositor support enabled";
#else
    qInfo() << "Wayland Compositor support disabled (not available on this platform)";
#endif

    QQmlApplicationEngine engine;

    qmlRegisterType<InputContext>("MarathonOS.Shell", 1, 0, "InputContext");

    auto *sessionStore = new SessionStore(&app);
    qmlRegisterSingletonInstance<SessionStore>("MarathonOS.Shell", 1, 0, "SessionStore",
                                               sessionStore);

    engine.addImageProvider("lunasvg", new LunaSvgImageProvider());

    engine.addImageProvider("lunasvgqrc", new LunaSvgImageProvider());
    qInfo() << "[MarathonShell] ✓ LunaSVG image provider registered";

    auto *ctx = engine.rootContext();

    createObject<ScreenMetrics>(ctx, "ScreenMetricsCpp", &app);

    createObject<MPRIS2Controller>(ctx, "MPRIS2Controller", &app);
    qInfo() << "[MarathonShell] ✓ MPRIS2 media controller initialized";

    auto *settingsManager = createObject<SettingsManager>(ctx, "SettingsManagerCpp", &app);
    auto *wallpaperStore  = new WallpaperStore(settingsManager, &app);
    qmlRegisterSingletonInstance<WallpaperStore>("MarathonOS.Shell", 1, 0, "WallpaperStore",
                                                 wallpaperStore);

    createObject<WaylandCompositorManager>(ctx, "WaylandCompositorManager", &app);
    if (debugEnabled || profileMode) {
        qWarning() << "[Profiler] Compositor Manager initialized:" << timer.elapsed() << "ms";
    }

    ctx->setContextProperty("MARATHON_DEBUG_ENABLED", debugEnabled);

#ifdef HAVE_WAYLAND
    ctx->setContextProperty("HAVE_WAYLAND", true);
#else
    ctx->setContextProperty("HAVE_WAYLAND", false);
#endif

    createObject<DesktopFileParser>(ctx, "DesktopFileParserCpp", &app);

    auto *appRegistry = createObject<MarathonAppRegistry>(ctx, "MarathonAppRegistry", &app);
    auto *appStore    = new AppStore(appRegistry, &app);
    qmlRegisterSingletonInstance<AppStore>("MarathonOS.Shell", 1, 0, "AppStore", appStore);
    auto *appScanner =
        createObject<MarathonAppScanner>(ctx, "MarathonAppScanner", appRegistry, &app);
    auto *appInstaller = createObject<MarathonAppInstaller>(ctx, "MarathonAppInstaller",
                                                            appRegistry, appScanner, &app);
    if (debugEnabled || profileMode) {
        qWarning() << "[Profiler] App System initialized:" << timer.elapsed() << "ms";
    }

    createObject<MarathonInputMethodEngine>(ctx, "InputMethodEngine", &app);
    qInfo() << "Input Method Engine initialized";

    auto *appModel          = createObject<AppModel>(ctx, "AppModel", &app);
    auto *taskModel         = createObject<TaskModel>(ctx, "TaskModel", &app);
    auto *notificationModel = createObject<NotificationModel>(ctx, "NotificationModel", &app);
    auto *navigationRouter  = createObject<NavigationRouterCpp>(ctx, "NavigationRouter", &app);
    createObject<StateManagerCpp>(ctx, "StateManager", &app);

    qmlRegisterUncreatableMetaObject(NotificationModel::staticMetaObject, "MarathonOS.Shell", 1, 0,
                                     "NotificationRoles", "Cannot create NotificationRoles enum");

    auto *networkManager   = createObject<NetworkManagerCpp>(ctx, "NetworkManagerCpp", &app);
    auto *powerManager     = createObject<PowerManagerCpp>(ctx, "PowerManagerService", &app);
    auto *rotationManager  = createObject<RotationManager>(ctx, "RotationManager", &app);
    auto *displayManager   = createObject<DisplayManagerCpp>(ctx, "DisplayManagerCpp", powerManager,
                                                             rotationManager, &app);
    auto *audioManager     = createObject<AudioManagerCpp>(ctx, "AudioManagerCpp", &app);
    auto *modemManager     = createObject<ModemManagerCpp>(ctx, "ModemManagerCpp", &app);
    auto *sensorManager    = createObject<SensorManagerCpp>(ctx, "SensorManagerCpp", &app);
    auto *bluetoothManager = createObject<BluetoothManager>(ctx, "BluetoothManagerCpp", &app);
    auto *locationManager  = createObject<LocationManager>(ctx, "LocationManager", &app);
    auto *hapticManager    = createObject<HapticManager>(ctx, "HapticManager", &app);
    createObject<ClipboardManagerCpp>(ctx, "ClipboardManagerCpp", settingsManager, &app);
    auto *alarmManager = createObject<AlarmManagerCpp>(
        ctx, "AlarmManagerCpp", settingsManager, powerManager, audioManager, hapticManager, &app);
    auto *flashlightManager = createObject<FlashlightManagerCpp>(ctx, "FlashlightManagerCpp", &app);
    auto *audioRoutingManager =
        createObject<AudioRoutingManager>(ctx, "AudioRoutingManagerCpp", &app);
    auto *securityManager = createObject<SecurityManager>(ctx, "SecurityManagerCpp", &app);

    auto *appLaunchService =
        createObject<AppLaunchService>(ctx, "AppLaunchService", appModel, taskModel, &app);
    createObject<UnifiedSearchServiceCpp>(ctx, "UnifiedSearchService", appModel, appRegistry,
                                          appScanner, settingsManager, navigationRouter,
                                          appLaunchService, &app);

    const QByteArray autoLaunchRaw = qgetenv("MARATHON_AUTO_LAUNCH_APP_ID").trimmed();
    if (!autoLaunchRaw.isEmpty()) {
        const QString autoAppId = QString::fromLocal8Bit(autoLaunchRaw);
        auto          launched  = std::make_shared<bool>(false);
        auto          tryLaunch = [appLaunchService, autoAppId, launched]() {
            if (!appLaunchService || *launched)
                return;
            if (!appLaunchService->compositor() || !appLaunchService->appWindow())
                return;
            *launched = true;
            QTimer::singleShot(0, appLaunchService, [appLaunchService, autoAppId]() {
                qWarning() << "[MarathonShell] Auto-launching app:" << autoAppId;
                appLaunchService->launchApp(autoAppId);
            });
        };
        QObject::connect(appLaunchService, &AppLaunchService::compositorChanged, &app, tryLaunch);
        QObject::connect(appLaunchService, &AppLaunchService::appWindowChanged, &app, tryLaunch);
        QTimer::singleShot(3000, &app, tryLaunch);
    }

    auto *appLifecycleManager = new AppLifecycleManager(taskModel, appLaunchService, &app);
    ctx->setContextProperty("AppLifecycleManager", appLifecycleManager);

    auto *hapticsObj =
        qobject_cast<HapticManager *>(ctx->contextProperty("HapticManager").value<QObject *>());

    auto *powerPolicyController = new PowerPolicyController(powerManager, displayManager, &app);
    ctx->setContextProperty("PowerPolicyControllerCpp", powerPolicyController);

    auto *displayPolicyController =
        new DisplayPolicyController(displayManager, settingsManager, &app);
    ctx->setContextProperty("DisplayPolicyControllerCpp", displayPolicyController);
    createObject<PowerBatteryHandlerCpp>(ctx, "PowerBatteryHandler", powerPolicyController,
                                         displayPolicyController, displayManager, hapticsObj, &app);
    auto *audioPolicyController =
        new AudioPolicyController(audioManager, settingsManager, hapticsObj, &app);
    ctx->setContextProperty("AudioPolicyControllerCpp", audioPolicyController);
    auto *notificationService = createObject<NotificationServiceCpp>(
        ctx, "NotificationService", notificationModel, settingsManager, audioPolicyController,
        hapticsObj, &app);
    auto *systemStatusStore =
        new SystemStatusStore(powerManager, networkManager, bluetoothManager, modemManager,
                              notificationService, settingsManager, &app);
    qmlRegisterSingletonInstance<SystemStatusStore>("MarathonOS.Shell", 1, 0, "SystemStatusStore",
                                                    systemStatusStore);
    auto *screenshotService = createObject<ScreenshotServiceCpp>(
        ctx, "ScreenshotService", audioPolicyController, hapticsObj, notificationService, &app);
    auto *systemControlStore = new SystemControlStore(
        networkManager, bluetoothManager, displayManager, flashlightManager, modemManager,
        settingsManager, alarmManager, locationManager, hapticManager, powerManager, audioManager,
        audioPolicyController, screenshotService, &app);
    qmlRegisterSingletonInstance<SystemControlStore>("MarathonOS.Shell", 1, 0, "SystemControlStore",
                                                     systemControlStore);
    auto *uiStore = new UIStore(&app);
    qmlRegisterSingletonInstance<UIStore>("MarathonOS.Shell", 1, 0, "UIStore", uiStore);
    auto *router = new Router(&app);
    qmlRegisterSingletonInstance<Router>("MarathonOS.Shell", 1, 0, "Router", router);
    auto *surfaceRegistry = new SurfaceRegistry(&app);
    qmlRegisterSingletonInstance<SurfaceRegistry>("MarathonOS.Shell", 1, 0, "SurfaceRegistry",
                                                  surfaceRegistry);

    createObject<CursorManager>(ctx, "CursorManager", &app);
    if (debugEnabled || profileMode) {
        qWarning() << "[Profiler] Hardware Managers initialized:" << timer.elapsed() << "ms";
    }

    QObject::connect(audioManager, &AudioManagerCpp::isPlayingChanged, powerManager,
                     [powerManager, audioManager]() {
                         if (audioManager->isPlaying()) {
                             powerManager->acquireWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback started - acquired wakelock";
                         } else {
                             powerManager->releaseWakelock("audio_playback");
                             qInfo()
                                 << "[MarathonShell] Audio playback stopped - released wakelock";
                         }
                     });
    qInfo() << "[MarathonShell] ✓ Audio playback wakelock integration enabled";

    auto *platform = createObject<PlatformCpp>(ctx, "Platform", &app);
    ctx->setContextProperty("PlatformCpp", platform);
    createObject<StatusBarIconServiceCpp>(ctx, "StatusBarIconService", &app);
    qInfo() << "[MarathonShell] ✓ Security Manager initialized (PAM + fprintd)";

    auto *wordEngine = createObject<WordEngine>(ctx, "WordEngine", &app);
    wordEngine->setLanguage("en_US");
    wordEngine->setEnabled(true);
    qInfo() << "[MarathonShell] ✓ Word Engine initialized";
    auto *emojiPredictor = new EmojiPredictor(&app);
    qmlRegisterSingletonInstance<EmojiPredictor>("MarathonOS.Shell", 1, 0, "EmojiPredictor",
                                                 emojiPredictor);
    auto *phrasePredictor = new PhrasePredictor(&app);
    qmlRegisterSingletonInstance<PhrasePredictor>("MarathonOS.Shell", 1, 0, "PhrasePredictor",
                                                  phrasePredictor);
    auto *dictionary = new Dictionary(wordEngine, emojiPredictor, phrasePredictor, &app);
    qmlRegisterSingletonInstance<Dictionary>("MarathonOS.Shell", 1, 0, "Dictionary", dictionary);
    auto *autoCorrect = new AutoCorrect(dictionary, &app);
    qmlRegisterSingletonInstance<AutoCorrect>("MarathonOS.Shell", 1, 0, "AutoCorrect", autoCorrect);
    auto *languageManager = new LanguageManager(settingsManager, wordEngine, &app);
    qmlRegisterSingletonInstance<LanguageManager>("MarathonOS.Shell", 1, 0, "LanguageManager",
                                                  languageManager);

    auto *rtScheduler = createObject<RTScheduler>(ctx, "RTScheduler", &app);
    if (rtScheduler->isRealtimeKernel()) {
        qInfo() << "[MarathonShell] RT Scheduler initialized (PREEMPT_RT kernel detected)";
        qInfo() << "[MarathonShell]   Current policy:" << rtScheduler->getCurrentPolicy()
                << "Priority:" << rtScheduler->getCurrentPriority();
    }

    qInfo() << "[MarathonShell] Initializing Marathon Service Bus (D-Bus)...";
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCritical() << "[MarathonShell] Failed to connect to D-Bus session bus!";
    } else {
        qInfo() << "[MarathonShell] ✓ Connected to D-Bus session bus";

        NotificationDatabase *notifDb = new NotificationDatabase(&app);
        if (!notifDb->initialize()) {
            qWarning() << "[MarathonShell] Failed to initialize notification database";
        }

        notificationModel->loadFromDatabase(notifDb);

        auto *freedesktopNotif = createObject<FreedesktopNotifications>(
            ctx, "FreedesktopNotifications", notifDb, notificationModel, powerManager, &app);
        if (freedesktopNotif->registerService()) {
            qInfo() << "[MarathonShell]   ✓ org.freedesktop.Notifications registered";
        }

        qInfo() << "[MarathonShell] Service bus ready (6 services active)";
    }
    if (debugEnabled) {
        qDebug() << "[Profiler] DBus Services initialized:" << timer.elapsed() << "ms";
    }

    auto *permissionManager =
        createObject<MarathonPermissionManager>(ctx, "PermissionManager", &app);
    qInfo() << "[MarathonShell] ✓ Permission Manager initialized";

    createObject<MarathonAppStoreService>(ctx, "AppStoreService", appInstaller, &app);
    qInfo() << "[MarathonShell] ✓ App Store Service initialized";

    auto *contactsManager    = createObject<ContactsManager>(ctx, "ContactsManager", &app);
    auto *telephonyService   = createObject<TelephonyService>(ctx, "TelephonyService", &app);
    auto *callHistoryManager = createObject<CallHistoryManager>(ctx, "CallHistoryManager", &app);
    auto *smsService         = createObject<SMSService>(ctx, "SMSService", &app);
    createObject<NotificationHandlerCpp>(ctx, "NotificationHandler", notificationService,
                                         navigationRouter, telephonyService, &app);
    createObject<TelephonyIntegrationCpp>(
        ctx, "TelephonyIntegration", contactsManager, notificationService, powerPolicyController,
        powerManager, displayPolicyController, displayManager, audioPolicyController, hapticsObj,
        telephonyService, smsService, &app);

    callHistoryManager->setContactsManager(contactsManager);
    smsService->setContactsManager(contactsManager);

    QObject::connect(telephonyService, &TelephonyService::callStateChanged, audioRoutingManager,
                     [audioRoutingManager](const QString &state) {
                         if (state == "active" || state == "incoming") {
                             audioRoutingManager->startCallAudio();
                         } else if (state == "idle" || state == "terminated") {
                             audioRoutingManager->stopCallAudio();
                         }
                     });
    qInfo() << "[MarathonShell] ✓ Audio routing wired to telephony";

    auto *mediaLibraryManager = createObject<MediaLibraryManager>(ctx, "MediaLibraryManager", &app);
    createObject<MusicLibraryManager>(ctx, "MusicLibraryManager", &app);

    {
        auto *ipc = new ShellIpcServer(
            permissionManager, contactsManager, callHistoryManager, telephonyService, smsService,
            mediaLibraryManager, settingsManager, bluetoothManager, displayManager, powerManager,
            audioManager, audioPolicyController, networkManager, hapticsObj, securityManager,
            sensorManager, locationManager, alarmManager, appLaunchService, &app);
        if (!ipc->registerOnSessionBus()) {
            qCritical()
                << "[MarathonShell] Failed to register app IPC on DBus (org.marathonos.Shell)";
        }
    }

    static qint64  callStartTime = 0;
    static QString lastCalledNumber;
    static bool    wasIncoming = false;

    QObject::connect(telephonyService, &TelephonyService::incomingCall, [](const QString &number) {
        callStartTime    = QDateTime::currentMSecsSinceEpoch();
        lastCalledNumber = number;
        wasIncoming      = true;
    });

    QObject::connect(telephonyService, &TelephonyService::callStateChanged, callHistoryManager,
                     [callHistoryManager, telephonyService](const QString &state) {
                         if (state == "active" && callStartTime == 0) {

                             callStartTime    = QDateTime::currentMSecsSinceEpoch();
                             lastCalledNumber = telephonyService->activeNumber();
                             wasIncoming      = false;
                         } else if (state == "idle" || state == "terminated") {

                             if (callStartTime > 0 && !lastCalledNumber.isEmpty()) {
                                 qint64  endTime  = QDateTime::currentMSecsSinceEpoch();
                                 int     duration = (endTime - callStartTime) / 1000;

                                 QString callType;
                                 if (wasIncoming) {

                                     callType = (duration > 0) ? "incoming" : "missed";
                                 } else {
                                     callType = "outgoing";
                                 }

                                 callHistoryManager->addCall(lastCalledNumber, callType,
                                                             callStartTime, duration);
                                 qInfo() << "[MarathonShell] ✓ Call logged:" << callType
                                         << lastCalledNumber << duration << "s";

                                 callStartTime = 0;
                                 lastCalledNumber.clear();
                                 wasIncoming = false;
                             }
                         }
                     });
    qInfo() << "[MarathonShell] ✓ Call history wired to telephony";

    appModel->loadFromRegistry(appRegistry);

    engine.addImportPath("qrc:/");

    QString userMarathonUIPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
    engine.addImportPath(userMarathonUIPath);
    qDebug() << "[QML Import] User-local MarathonUI:" << userMarathonUIPath;

    QString systemMarathonUIPath = "/usr/lib/qt6/qml";
    engine.addImportPath(systemMarathonUIPath);
    qDebug() << "[QML Import] System-wide Qt modules:" << systemMarathonUIPath;

    QString localSystemMarathonUIPath = "/usr/local/lib/qt6/qml";
    engine.addImportPath(localSystemMarathonUIPath);
    qDebug() << "[QML Import] Local System-wide Qt modules:" << localSystemMarathonUIPath;

    QString buildMarathonUIPath = QCoreApplication::applicationDirPath() + "/..";
    engine.addImportPath(buildMarathonUIPath);
    qDebug() << "[QML Import] Build directory:" << buildMarathonUIPath;

    QDir themeCheck1(userMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck2(systemMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck2b(localSystemMarathonUIPath + "/MarathonUI/Theme");
    QDir themeCheck3(buildMarathonUIPath + "/MarathonUI/Theme");

    bool marathonUIFound = themeCheck1.exists() || themeCheck2.exists() || themeCheck2b.exists() ||
        themeCheck3.exists();

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
        qCritical() << "  1." << themeCheck1.absolutePath()
                    << (themeCheck1.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  2." << themeCheck2.absolutePath()
                    << (themeCheck2.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  3." << themeCheck2b.absolutePath()
                    << (themeCheck2b.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "  4." << themeCheck3.absolutePath()
                    << (themeCheck3.exists() ? " [FOUND]" : " [NOT FOUND]");
        qCritical() << "";
        qCritical() << "========================================================================";
        qCritical() << "";

    } else {
        qInfo() << "[MarathonShell] ✓ MarathonUI modules found";
        if (themeCheck1.exists())
            qDebug() << "  - Using user-local installation";
        else if (themeCheck2.exists())
            qDebug() << "  - Using system-wide installation";
        else if (themeCheck3.exists())
            qDebug() << "  - Using build directory (development mode)";
    }

    const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));

    qRegisterMetaType<GeoClueTimestamp>("GeoClueTimestamp");
    qDBusRegisterMetaType<GeoClueTimestamp>();

    const auto devices = QInputDevice::devices();
#if !defined(QT_NO_INFO_OUTPUT)
    qInfo() << "[MarathonShell] Detected Input Devices:";
    for (const QInputDevice *device : devices) {
        qInfo() << "  -" << device->name() << "Type:" << device->type()
                << "ID:" << device->systemId() << "Seat:" << device->seatName();
    }
#else
    Q_UNUSED(devices)
#endif

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML";
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }

    QTimer::singleShot(
        0, &app, [&app, settingsManager, appModel, appRegistry, appScanner, permissionManager]() {
            const QStringList searchPaths = {
                "/usr/share/applications", "/usr/local/share/applications",
                QDir::homePath() + "/.local/share/applications",
                "/var/lib/flatpak/exports/share/applications",
                QDir::homePath() + "/.local/share/flatpak/exports/share/applications"};

            const bool filterMobile = settingsManager->filterMobileFriendlyApps();

#ifdef HAVE_QT_CONCURRENT
            auto *watcher = new QFutureWatcher<QVariantList>(&app);
            QObject::connect(watcher, &QFutureWatcher<QVariantList>::finished, &app,
                             [watcher, appModel]() {
                                 const QVariantList nativeApps = watcher->result();
                                 appModel->addApps(nativeApps);
                                 watcher->deleteLater();
                             });

            QFuture<QVariantList> future = QtConcurrent::run([searchPaths, filterMobile]() {
                DesktopFileParser parser;
                return parser.scanApplications(searchPaths, filterMobile);
            });
            watcher->setFuture(future);
#else
        DesktopFileParser parser;
        const QVariantList nativeApps = parser.scanApplications(searchPaths, filterMobile);
        appModel->addApps(nativeApps);
#endif

            auto grantProtected = [permissionManager, appRegistry](const QString &appId) {
                if (!permissionManager || !appRegistry)
                    return;
                auto *info = appRegistry->getAppInfo(appId);
                if (!info || !info->isProtected)
                    return;
                for (const QString &perm : info->permissions) {
                    if (!perm.isEmpty())
                        permissionManager->setPermission(appId, perm, true, true);
                }
            };

            QObject::connect(appScanner, &MarathonAppScanner::appDiscovered, &app, grantProtected);
            QObject::connect(appScanner, &MarathonAppScanner::scanComplete, &app,
                             [appModel, appRegistry, grantProtected](int) {
                                 for (const QString &id : appRegistry->getAllAppIds())
                                     grantProtected(id);
                                 appModel->loadFromRegistry(appRegistry);
                             });

#ifdef HAVE_QT_CONCURRENT
            appScanner->scanApplicationsAsync();
#else
        appScanner->scanApplications();
#endif
        });

    qDebug() << "Marathon OS Shell started";
    return app.exec();
}
