#include <QGuiApplication>
#include <QQuickView>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QCommandLineParser>
#include <QCommandLineOption>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QDebug>
#include <QUrl>
#include <QTimer>
#include <QQuickItem>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QColor>
#include <QDateTime>
#include <QTimeZone>
#include <QVariantMap>
#include <QtQml/qqml.h>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusError>
#include <atomic>
#include <cstring>

// Tiny QObject helper that exposes QTimeZone to QML. Qt's QML JS engine
// silently ignores the `timeZone` option on Date.toLocaleString, so apps
// that need DST-correct wall-clock times across IANA zones can't use the
// pure-JS path. WorldClockHelper.timeIn("America/New_York") returns the
// formatted time/weekday/offset map.
class WorldClockHelper : public QObject {
    Q_OBJECT
  public:
    explicit WorldClockHelper(QObject *parent = nullptr)
        : QObject(parent) {}

    Q_INVOKABLE QVariantMap timeIn(const QString &tzId) const {
        QVariantMap out;
        QTimeZone   tz(tzId.toUtf8());
        if (!tz.isValid()) {
            out["time"]        = "—:—";
            out["weekday"]     = "";
            out["offsetLabel"] = tzId;
            return out;
        }
        const QDateTime now      = QDateTime::currentDateTime();
        const QDateTime targetTz = now.toTimeZone(tz);
        out["time"]              = targetTz.toString("h:mm AP");
        out["weekday"]           = targetTz.toString("ddd").toUpper();

        // Offset relative to local in hours (DST-aware via QTimeZone).
        const int targetOffset = tz.offsetFromUtc(now);
        const int localOffset  = QTimeZone::systemTimeZone().offsetFromUtc(now);
        const int diffHours    = (targetOffset - localOffset) / 3600;
        if (diffHours == 0)
            out["offsetLabel"] = "Local";
        else
            out["offsetLabel"] = QString("%1%2h").arg(diffHours > 0 ? "+" : "").arg(diffHours);
        return out;
    }
};

#include "util/frametiming.h"
#include "util/rtprio.h"

#ifdef Q_OS_LINUX
// Foreground app: main thread RR/4, render thread RR/3 -- see
// docs/RT_SCHEDULING.md for the full hierarchy and rationale.
constexpr int           kForegroundMainPriority   = 4;
constexpr int           kForegroundRenderPriority = 3;

static std::atomic<int> g_desiredRenderPriority{0};

// Render thread (called from beforeSynchronizing on the render thread).
static void applyRenderPriorityIfNeeded() {
    static int last = -1;
    const int  want = g_desiredRenderPriority.load(std::memory_order_relaxed);
    if (want == last)
        return;
    const int rc = marathon::rt::setCurrentThreadPriority(want);
    last         = want;
    if (rc != 0) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            qInfo() << "[AppRunner] Render-thread RT elevation skipped (rtprio rlimit not "
                       "granted):"
                    << strerror(rc);
        }
    }
}

// Main thread (called directly from activeChanged on main thread).
static void applyMainPriorityForActive(bool active) {
    static int last = -1;
    const int  want = active ? kForegroundMainPriority : 0;
    if (want == last)
        return;
    const int rc = marathon::rt::setCurrentThreadPriority(want);
    last         = want;
    if (rc != 0) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            qInfo() << "[AppRunner] Main-thread RT elevation skipped:" << strerror(rc);
        }
    }
}
#endif

#include "marathonappregistry.h"
#include "marathonappscanner.h"
#include "marathonappinstaller.h"

#include "ipc/shellipcclients.h"
#include "calendarmanagercpp.h"

class AppRunnerLifecycleObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.AppRunner.Lifecycle1")

  public:
    explicit AppRunnerLifecycleObject(QObject *parent = nullptr)
        : QObject(parent) {
        const QByteArray shellPidRaw = qgetenv("MARATHON_SHELL_PID").trimmed();
        bool             ok          = false;
        m_expectedShellPid           = shellPidRaw.toLongLong(&ok);
        if (!ok)
            m_expectedShellPid = -1;
    }

    void setRoot(QObject *root) {
        m_root = root;
    }

  public slots:
    bool Back() {
        if (!verifyCallerIsShell())
            return false;
        return invokeBool("handleBack");
    }
    bool Forward() {
        if (!verifyCallerIsShell())
            return false;
        return invokeBool("handleForward");
    }

  private:
    bool verifyCallerIsShell() {
        if (!calledFromDBus())
            return false;
        if (m_expectedShellPid <= 0) {
            sendErrorReply(QDBusError::AccessDenied, "MARATHON_SHELL_PID not set");
            return false;
        }
        const QString sender = message().service();
        auto          pidR   = connection().interface()->servicePid(sender);
        if (!pidR.isValid()) {
            sendErrorReply(QDBusError::AccessDenied, "Unable to resolve sender PID");
            return false;
        }
        if (static_cast<qint64>(pidR.value()) != m_expectedShellPid) {
            sendErrorReply(QDBusError::AccessDenied, "Caller is not the shell");
            return false;
        }
        return true;
    }

    bool invokeBool(const char *method) {
        if (!m_root) {
            sendErrorReply(QDBusError::Failed, "App root not ready");
            return false;
        }

        QVariant ret;
        bool     ok = QMetaObject::invokeMethod(m_root.data(), method, Qt::DirectConnection,
                                                Q_RETURN_ARG(QVariant, ret));
        if (!ok) {

            QMetaObject::invokeMethod(m_root.data(),
                                      QByteArray(method) == "handleBack" ? "backPressed" :
                                                                           "forwardPressed",
                                      Qt::DirectConnection);
            return true;
        }
        return ret.toBool();
    }

    qint64            m_expectedShellPid = -1;
    QPointer<QObject> m_root;
};

static QString capitalizeAppId(const QString &appId) {
    if (appId.isEmpty())
        return appId;
    return appId.left(1).toUpper() + appId.mid(1);
}

static QString readTextFile(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(f.readAll());
}

static bool copyDirRecursively(const QString &srcPath, const QString &dstPath) {
    const QDir src(srcPath);
    if (!src.exists())
        return false;

    QDir dst(dstPath);
    if (!dst.exists()) {
        if (!QDir().mkpath(dstPath))
            return false;
    }

    const QFileInfoList entries = src.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);
    for (const QFileInfo &fi : entries) {
        const QString srcItem = fi.absoluteFilePath();
        const QString dstItem = dst.filePath(fi.fileName());

        if (fi.isDir()) {
            if (!copyDirRecursively(srcItem, dstItem))
                return false;
        } else {

            if (QFileInfo::exists(dstItem))
                QFile::remove(dstItem);
            if (!QFile::copy(srcItem, dstItem))
                return false;
        }
    }

    return true;
}

static QString createPatchedQmldirWithoutPrefer(const QString &importRoot,
                                                const QString &moduleRelDir) {
    const QDir    importDir(importRoot);
    const QString moduleAbsDir = importDir.filePath(moduleRelDir);
    const QString qmldirAbs    = QDir(moduleAbsDir).filePath("qmldir");

    const QString qmldirText = readTextFile(qmldirAbs);
    if (qmldirText.isEmpty())
        return {};

    if (!qmldirText.contains("prefer :/qt/qml/"))
        return {};

    const QString tmpBase =
        QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/marathon-app-runner";
    // Suffix the tmp root with a hash of the source path so multiple
    // calls within one process (e.g. dev build + a stale install)
    // each land in their own staging dir. Reusing a single
    // pid-keyed dir across sources would let the second call's
    // qmldir replace the first while keeping the first call's
    // files, leaving orphan type declarations behind.
    const quint64 srcHash =
        qHash(importRoot + ":" + moduleRelDir, qHash(QByteArray("marathon-app-runner")));
    QString tmpRoot = tmpBase +
        QString("/shell-qmldir-%1-%2")
            .arg(QCoreApplication::applicationPid())
            .arg(srcHash, 16, 16, QChar('0'));
    const QString tmpModuleDir = QDir(tmpRoot).filePath(moduleRelDir);

    QDir().mkpath(tmpModuleDir);

    QString     patched;
    QTextStream out(&patched);

    // Type declarations in qmldir look like "Name 1.0 path/file.qml"
    // or "singleton Name 1.0 path/file.qml". If the referenced file
    // doesn't exist alongside the patched qmldir we drop the line —
    // stale installs accrue orphan declarations (we hit this with
    // an AlarmManager singleton that survived deletion of its .qml)
    // and Qt's resolver chases the orphan into a `Type X
    // unavailable` cascade.
    const QStringList lines = qmldirText.split('\n');
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        if (line.startsWith("prefer "))
            continue;

        const QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
        const bool        looksLikeTypeDecl = parts.size() >= 3 && parts.last().endsWith(".qml") &&
            !line.startsWith("module ") && !line.startsWith("plugin ") &&
            !line.startsWith("classname ") && !line.startsWith("typeinfo ") &&
            !line.startsWith("depends ") && !line.startsWith("import ") &&
            !line.startsWith("linktarget ");
        if (looksLikeTypeDecl) {
            const QString relTarget = parts.last();
            const QString srcCheck  = QDir(moduleAbsDir).filePath(relTarget);
            if (!QFileInfo::exists(srcCheck))
                continue;
        }

        out << line << '\n';
    }

    QFile f(QDir(tmpModuleDir).filePath("qmldir"));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate))
        return {};
    f.write(patched.toUtf8());
    f.close();

    const QString srcQmlDir = QDir(moduleAbsDir).filePath("qml");
    const QString dstQmlDir = QDir(tmpModuleDir).filePath("qml");
    if (!QDir(dstQmlDir).exists()) {
        if (!copyDirRecursively(srcQmlDir, dstQmlDir))
            return {};
    }

    const QString srcTypes = QDir(moduleAbsDir).filePath("marathon-shell.qmltypes");
    const QString dstTypes = QDir(tmpModuleDir).filePath("marathon-shell.qmltypes");
    if (QFileInfo::exists(srcTypes) && !QFileInfo::exists(dstTypes))
        QFile::copy(srcTypes, dstTypes);

    return tmpRoot;
}

struct QmldirInfo {
    QString moduleUri;
    QString componentVersion;
};

static QmldirInfo parseQmldirForComponent(const QString &qmldirPath, const QString &componentName) {
    QmldirInfo    out;
    const QString text = readTextFile(qmldirPath);
    if (text.isEmpty())
        return out;

    const QStringList lines = text.split('\n');
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        if (line.startsWith("module ")) {
            out.moduleUri = line.mid(QString("module ").size()).trimmed();
            continue;
        }

        if (line.startsWith(componentName + ' ')) {
            const QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
            if (parts.size() >= 2)
                out.componentVersion = parts.at(1).trimmed();
        }
    }

    return out;
}

static QString findAppQmldirPath(const QString &appAbsolutePath, const QString &appId) {

    QString p1 = QDir(appAbsolutePath)
                     .filePath(QStringLiteral("MarathonApp/%1/qmldir").arg(capitalizeAppId(appId)));
    if (QFileInfo::exists(p1))
        return p1;

    const QDir root(QDir(appAbsolutePath).filePath("MarathonApp"));
    if (!root.exists())
        return {};

    const QStringList children = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &child : children) {
        const QString cand = root.filePath(child + "/qmldir");
        if (QFileInfo::exists(cand))
            return cand;
    }

    return {};
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName("marathon-app-runner");
    QCoreApplication::setOrganizationName("Marathon OS");

    QCommandLineParser parser;
    parser.setApplicationDescription(
        "Marathon App Runner (Wayland client) - runs a Marathon QML app out-of-process");
    parser.addHelpOption();

    QCommandLineOption appIdOpt(QStringList() << "a"
                                              << "app-id",
                                "Marathon app id (e.g. phone, calculator)", "appId");
    parser.addOption(appIdOpt);
    QCommandLineOption routeOpt(QStringList() << "r"
                                              << "route",
                                "In-app route to open (e.g. /emergency)", "route");
    parser.addOption(routeOpt);
    parser.process(app);

    const QString appId = parser.value(appIdOpt).trimmed();
    if (appId.isEmpty()) {
        qCritical() << "[marathon-app-runner] Missing --app-id";
        return 2;
    }
    // Route may also arrive via env (when shell sets MARATHON_APP_ROUTE).
    // CLI flag wins, then env, then empty.
    QString launchRoute = parser.value(routeOpt).trimmed();
    if (launchRoute.isEmpty())
        launchRoute = qEnvironmentVariable("MARATHON_APP_ROUTE");
    const QString launchRouteParams = qEnvironmentVariable("MARATHON_APP_ROUTE_PARAMS");

    QGuiApplication::setDesktopFileName(appId);

    MarathonAppRegistry registry;
    MarathonAppScanner  scanner(&registry);

    // Fast path: only parse this app's manifest, not every installed app.
    // Falling back to a full scan if the targeted parse fails preserves the
    // previous behaviour for apps that ship in non-standard layouts (e.g.
    // a future per-user install dir not yet on the search path).
    if (!scanner.scanSingleApp(appId)) {
        qWarning() << "[marathon-app-runner] Single-app scan miss for" << appId
                   << "-- falling back to full scan";
        scanner.scanApplications();
    }

    MarathonAppRegistry::AppInfo *info = registry.getAppInfo(appId);
    if (!info) {
        qCritical() << "[marathon-app-runner] App not found in registry:" << appId;
        return 3;
    }

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setTitle(info->name);

    view.setColor(Qt::transparent);

#ifdef Q_OS_LINUX
    // On window active-state change (handler runs on GUI/main thread):
    //   1. Elevate / demote the main thread directly (we're on it).
    //   2. Set desired render-thread priority for the render thread to pick up.
    //   3. view.update() forces one more sync so beforeSynchronizing fires once
    //      more -- guarantees a demotion lands on the render thread even when
    //      the app has otherwise stopped requesting frames (backgrounded).
    QObject::connect(&view, &QWindow::activeChanged, &view, [&view]() {
        const bool active = view.isActive();
        applyMainPriorityForActive(active);
        g_desiredRenderPriority.store(active ? kForegroundRenderPriority : 0,
                                      std::memory_order_relaxed);
        view.update();
    });
    QObject::connect(
        &view, &QQuickWindow::beforeSynchronizing, &view, []() { applyRenderPriorityIfNeeded(); },
        Qt::DirectConnection);
#endif

    if (qEnvironmentVariableIntValue("MARATHON_FRAME_TIMING") != 0)
        marathon::diag::installFrameTimingTracker(&view, QStringLiteral("app:%1").arg(appId));

    const int w = qEnvironmentVariableIntValue("MARATHON_APP_WIDTH") > 0 ?
        qEnvironmentVariableIntValue("MARATHON_APP_WIDTH") :
        540;
    const int h = qEnvironmentVariableIntValue("MARATHON_APP_HEIGHT") > 0 ?
        qEnvironmentVariableIntValue("MARATHON_APP_HEIGHT") :
        1140;
    view.resize(w, h);

    QQmlEngine *engine = view.engine();

    if (QDir(info->absolutePath).exists())
        engine->addImportPath(info->absolutePath);

    {
        const QDir        binDir(QCoreApplication::applicationDirPath());
        const QDir        cwd(QDir::currentPath());

        const QStringList devCandidates = {

            binDir.filePath("../../../build-ui"),

            binDir.filePath("../../build-ui"),
            binDir.filePath("../build-ui"),
            cwd.filePath("build-ui"),
            cwd.filePath("../build-ui"),
        };

        bool foundUi = false;
        for (const QString &cand : devCandidates) {
            if (QDir(cand + "/MarathonUI").exists()) {
                engine->addImportPath(cand);
                foundUi = true;
                break;
            }
        }

        const QString userUi =
            QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/marathon-ui";
        if (QDir(userUi + "/MarathonUI").exists()) {
            engine->addImportPath(userUi);
            foundUi = true;
        }

        if (QDir("/usr/lib/qt6/qml/MarathonUI").exists()) {
            engine->addImportPath("/usr/lib/qt6/qml");
            foundUi = true;
        }
        if (QDir("/usr/lib64/qt6/qml/MarathonUI").exists()) {
            engine->addImportPath("/usr/lib64/qt6/qml");
            foundUi = true;
        }
        if (QDir("/usr/local/lib/qt6/qml/MarathonUI").exists()) {
            engine->addImportPath("/usr/local/lib/qt6/qml");
            foundUi = true;
        }
        if (QDir("/usr/local/lib64/qt6/qml/MarathonUI").exists()) {
            engine->addImportPath("/usr/local/lib64/qt6/qml");
            foundUi = true;
        }

        if (!foundUi) {
            qWarning()
                << "[marathon-app-runner] MarathonUI import root not found. Apps may fail to load.";
        }
    }

    // MarathonOS.Shell resolution.
    //
    // We've hit a stale-install footgun in the past: an old
    // /usr/local/lib/qt6/qml/MarathonOS/Shell/ left over from a
    // prior packaging run declared `singleton AlarmManager 1.0
    // qml/services/AlarmManager.qml` in its qmldir, but the
    // corresponding .qml file had already been removed from the
    // source tree. Because the MarathonUI fallback loop above
    // adds /usr/local/lib/qt6/qml to the engine's import paths
    // (and Qt searches first-added-first), the stale install
    // would win lookup over the development build, every app
    // that imported MarathonOS.Shell would inherit the broken
    // AlarmManager declaration, and Settings would refuse to
    // load with `Type AlarmManager unavailable` chasing up the
    // type-resolution chain.
    //
    // We patch this on two axes:
    //   1. Re-walk all candidate roots even when
    //      MARATHON_SHELL_QML_IMPORT_PATH is set, so a stale
    //      install also gets visited by the patcher (which now
    //      drops qmldir entries whose target files don't exist
    //      on disk — see createPatchedQmldirWithoutPrefer).
    //   2. Prepend the dev build's patched root to the engine's
    //      import path list so it wins resolution over any
    //      install path that the MarathonUI loop already added.
    QStringList shellImportPaths;
    auto        considerShellRoot = [&](const QString &cand) {
        if (cand.isEmpty() || !QDir(cand).exists())
            return;
        if (!QDir(cand + "/MarathonOS/Shell").exists())
            return;
        const QString patched = createPatchedQmldirWithoutPrefer(cand, "MarathonOS/Shell");
        shellImportPaths.append(patched.isEmpty() ? cand : patched);
    };

    const QByteArray shellQmlEnv = qgetenv("MARATHON_SHELL_QML_IMPORT_PATH").trimmed();
    if (!shellQmlEnv.isEmpty())
        considerShellRoot(QString::fromLocal8Bit(shellQmlEnv));

    {
        const QDir        binDir(QCoreApplication::applicationDirPath());
        const QStringList candidates = {
            binDir.filePath("../../shell/qml"),
            binDir.filePath("../shell/qml"),
            binDir.filePath("shell/qml"),
            "/usr/local/lib/qt6/qml",
            "/usr/lib/qt6/qml",
            "/usr/lib64/qt6/qml",
        };
        for (const QString &cand : candidates)
            considerShellRoot(cand);
    }

    // Reorder: shell roots first (dev build/env winning over
    // anything the MarathonUI loop added). QQmlEngine's import
    // search is first-added-first.
    const QStringList existing = engine->importPathList();
    engine->setImportPathList(shellImportPaths + existing);

    engine->addImportPath("qrc:/");
    engine->addImportPath(":/");

    auto *ctx = view.rootContext();
    ctx->setContextProperty("MarathonAppRegistry", &registry);
    ctx->setContextProperty("MarathonAppInstaller",
                            new MarathonAppInstaller(&registry, &scanner, ctx));

    // Mirror the shell's MARATHON_DEBUG flag into the runner so Logger.info()
    // and the test-app auto-run path actually emit. Without this, every
    // Logger.info() in app QML is silently dropped because Constants.qml's
    // debugMode resolves to false in the runner process.
    {
        const QByteArray dbg = qgetenv("MARATHON_DEBUG");
        const bool       on  = (dbg == "1" || dbg.toLower() == "true");
        ctx->setContextProperty("MARATHON_DEBUG_ENABLED", on);
    }

    // Expose the launch route so apps can show a route-specific entry point
    // (the lock-screen Emergency affordance launches phone with /emergency).
    ctx->setContextProperty("MARATHON_APP_ROUTE", launchRoute);
    ctx->setContextProperty("MARATHON_APP_ROUTE_PARAMS", launchRouteParams);

    // The shell forwards its current user scale factor and detected DPI in
    // env vars so the app can size in lockstep with shell chrome. Without
    // this, Constants.scaleFactor inside the sandbox always evaluates to
    // 1.0 (no SettingsManagerCpp / ScreenMetricsCpp inside the bwrap), so
    // the status bar can be 2x while app content stays at 1x.
    {
        bool         ok        = false;
        const double envScale  = qEnvironmentVariable("MARATHON_USER_SCALE", "1.0").toDouble(&ok);
        const double userScale = (ok && envScale > 0) ? envScale : 1.0;
        const double envDpi    = qEnvironmentVariable("MARATHON_DPI", "160.0").toDouble(&ok);
        const double dpi       = (ok && envDpi > 0) ? envDpi : 160.0;
        ctx->setContextProperty("MARATHON_USER_SCALE", userScale);
        ctx->setContextProperty("MARATHON_DPI", dpi);
    }

    const auto hasPerm = [&](const QString &perm) -> bool {
        return std::find(info->permissions.begin(), info->permissions.end(), perm) !=
            info->permissions.end();
    };

    // Construct only the IPC clients whose permissions the app actually
    // declared. Each client constructor does a sync D-Bus introspect + a
    // handful of signal subscriptions + an initial state refresh -- across
    // ~13 clients that's ~50-150 round-trips on cold start, none of which a
    // perm-less app like Calculator can use anyway (the shell rejects every
    // call with AccessDenied).
    //
    // PermissionClient, NavigationClient and HapticClient are unconditional:
    // every app uses back/close gestures (Navigation), Marathon UI hooks
    // haptic feedback on standard buttons, and apps need PermissionClient to
    // introspect their own grants.
    // Unconditional: every app gets the world-clock / timezone helper
    // (lightweight, no IPC, no permissions).
    ctx->setContextProperty("WorldClockHelper", new WorldClockHelper(&app));

    ctx->setContextProperty("PermissionManager", new PermissionClient(&app));

    if (hasPerm("contacts"))
        ctx->setContextProperty("ContactsManager", new ContactsClient(&app));
    if (hasPerm("telephony") || hasPerm("phone"))
        ctx->setContextProperty("CallHistoryManager", new CallHistoryClient(&app));
    if (hasPerm("telephony") || hasPerm("phone"))
        ctx->setContextProperty("TelephonyService", new TelephonyClient(appId, &app));
    if (hasPerm("sms") || hasPerm("telephony"))
        ctx->setContextProperty("SMSService", new SmsClient(appId, &app));

    if (hasPerm("storage"))
        ctx->setContextProperty("MediaLibraryManager", new MediaLibraryClient(appId, &app));

    SettingsClient *settingsClient = nullptr;
    if (hasPerm("system") || hasPerm("storage")) {
        settingsClient = new SettingsClient(appId, &app);
        ctx->setContextProperty("SettingsManagerCpp", settingsClient);
    }

    if (hasPerm("system")) {
        ctx->setContextProperty("BluetoothManagerCpp", new BluetoothClient(appId, &app));
        ctx->setContextProperty("DisplayManagerCpp", new DisplayClient(appId, &app));
        ctx->setContextProperty("PowerManagerService", new PowerClient(appId, &app));
        ctx->setContextProperty("AudioManagerCpp", new AudioClient(appId, &app));
        ctx->setContextProperty("SecurityManagerCpp", new SecurityClient(appId, &app));
    }

    if (hasPerm("network"))
        ctx->setContextProperty("NetworkManagerCpp", new NetworkClient(appId, &app));

    auto *navigationClient = new NavigationClient(&app);
    ctx->setContextProperty("NavigationService", navigationClient);
    ctx->setContextProperty("NavigationRouter", navigationClient);
    ctx->setContextProperty("HapticService", new HapticClient(&app));

    NotificationClient *notificationClient = nullptr;
    if (hasPerm("notifications")) {
        notificationClient = new NotificationClient(appId, &app);
        ctx->setContextProperty("NativeNotificationService", notificationClient);
        // Apps and the test suite consume this under the shorter name.
        ctx->setContextProperty("NotificationService", notificationClient);
    }
    if (hasPerm("sensors") || hasPerm("system"))
        ctx->setContextProperty("SensorService", new SensorClient(&app));
    if (hasPerm("location"))
        ctx->setContextProperty("LocationService", new LocationClient(&app));
    if (hasPerm("alarms") || hasPerm("system"))
        ctx->setContextProperty("AlarmService", new AlarmClient(&app));
    if (hasPerm("system"))
        ctx->setContextProperty("UpdateService", new UpdateClient(&app));
    if (hasPerm("storage"))
        ctx->setContextProperty("DavSyncEngine", new DavClient(&app));

    auto *systemStatusStore = new SystemStatusStoreClient(
        qobject_cast<PowerClient *>(ctx->contextProperty("PowerManagerService").value<QObject *>()),
        qobject_cast<NetworkClient *>(ctx->contextProperty("NetworkManagerCpp").value<QObject *>()),
        &app);
    qmlRegisterSingletonInstance<SystemStatusStoreClient>("MarathonOS.Shell", 1, 0,
                                                          "SystemStatusStore", systemStatusStore);
    auto *systemControlStore = new SystemControlStoreClient(
        qobject_cast<NetworkClient *>(ctx->contextProperty("NetworkManagerCpp").value<QObject *>()),
        qobject_cast<BluetoothClient *>(
            ctx->contextProperty("BluetoothManagerCpp").value<QObject *>()),
        qobject_cast<DisplayClient *>(ctx->contextProperty("DisplayManagerCpp").value<QObject *>()),
        settingsClient,
        qobject_cast<AudioClient *>(ctx->contextProperty("AudioManagerCpp").value<QObject *>()),
        &app);
    qmlRegisterSingletonInstance<SystemControlStoreClient>(
        "MarathonOS.Shell", 1, 0, "SystemControlStore", systemControlStore);

    if (appId == "calendar") {
        ctx->setContextProperty("CalendarManager",
                                new CalendarManagerCpp(settingsClient, notificationClient, &app));
    }

    const QString entryAbs      = QDir(info->absolutePath).filePath(info->entryPoint);
    const QUrl    entryUrl      = QUrl::fromLocalFile(entryAbs);
    const QString componentName = QFileInfo(info->entryPoint).completeBaseName();

    qInfo() << "[marathon-app-runner] Starting app" << appId << "entryPoint" << info->entryPoint
            << "entryAbs" << entryAbs << "appPath" << info->absolutePath;

    view.show();

    AppRunnerLifecycleObject lifecycleObj;
    {
        const qint64  pid = QCoreApplication::applicationPid();

        const QString serviceName = QStringLiteral("org.marathonos.AppRunner.pid%1").arg(pid);
        auto          bus         = QDBusConnection::sessionBus();
        if (bus.isConnected()) {
            if (!bus.registerService(serviceName)) {
                qWarning() << "[marathon-app-runner] Failed to register DBus service" << serviceName
                           << ":" << bus.lastError().message();
            }
            if (!bus.registerObject(QStringLiteral("/org/marathonos/AppRunner/Lifecycle"),
                                    &lifecycleObj, QDBusConnection::ExportAllSlots)) {
                qWarning() << "[marathon-app-runner] Failed to register lifecycle object:"
                           << bus.lastError().message();
            }
        } else {
            qWarning()
                << "[marathon-app-runner] Session bus not connected; nav gestures won't work";
        }
    }

    const QString appAbsPath = info->absolutePath;

    QTimer::singleShot(
        0, &view,
        [&view, engine, ctx, entryUrl, entryAbs, appId, componentName, appAbsPath,
         &lifecycleObj]() {
            QQmlComponent *component = nullptr;

            if (QFileInfo::exists(entryAbs)) {
                component = new QQmlComponent(engine, entryUrl, &view);
            } else {
                const QString    qmldirPath = findAppQmldirPath(appAbsPath, appId);
                const QmldirInfo qmldir     = parseQmldirForComponent(qmldirPath, componentName);

                if (qmldir.moduleUri.isEmpty()) {
                    qCritical() << "[marathon-app-runner] Entry point file not found and no qmldir "
                                   "module found for"
                                << appId << "entryAbs=" << entryAbs << "qmldir=" << qmldirPath;
                    QCoreApplication::exit(4);
                    return;
                }

                QString wrapper;
                wrapper += "import QtQuick\n";
                if (!qmldir.componentVersion.isEmpty())
                    wrapper +=
                        QString("import %1 %2\n").arg(qmldir.moduleUri, qmldir.componentVersion);
                else
                    wrapper += QString("import %1\n").arg(qmldir.moduleUri);
                wrapper += QString("%1 { }\n").arg(componentName);

                component = new QQmlComponent(engine, &view);
                component->setData(
                    wrapper.toUtf8(),
                    QUrl(QStringLiteral("marathon-app:///%1/Wrapper.qml").arg(appId)));
            }

            auto createAndAttach = [component, &view, ctx, appId, &lifecycleObj]() {
                if (!component) {
                    QCoreApplication::exit(4);
                    return;
                }

                if (component->isError()) {
                    qCritical() << "[marathon-app-runner] QML component error for" << appId << ":"
                                << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                if (component->status() != QQmlComponent::Ready) {
                    qCritical() << "[marathon-app-runner] QML component not ready for" << appId
                                << "status=" << component->status()
                                << "errors=" << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                QObject *rootObj = component->create(ctx);
                if (!rootObj) {
                    qCritical() << "[marathon-app-runner] Failed to create app instance for"
                                << appId << ":" << component->errorString();
                    QCoreApplication::exit(4);
                    return;
                }

                auto *rootItem = qobject_cast<QQuickItem *>(rootObj);
                if (!rootItem) {
                    qCritical() << "[marathon-app-runner] App root is not a QQuickItem for"
                                << appId;
                    rootObj->deleteLater();
                    QCoreApplication::exit(4);
                    return;
                }

                rootItem->setParentItem(view.contentItem());
                rootItem->setWidth(view.width());
                rootItem->setHeight(view.height());

                rootItem->forceActiveFocus();

                QObject::connect(&view, &QQuickView::widthChanged, rootItem,
                                 [&view, rootItem](int) { rootItem->setWidth(view.width()); });
                QObject::connect(&view, &QQuickView::heightChanged, rootItem,
                                 [&view, rootItem](int) { rootItem->setHeight(view.height()); });

                lifecycleObj.setRoot(rootObj);
            };

            if (component->status() == QQmlComponent::Loading) {

                QObject::connect(component, &QQmlComponent::statusChanged, &view,
                                 [component, createAndAttach](QQmlComponent::Status st) {
                                     if (st == QQmlComponent::Ready || st == QQmlComponent::Error)
                                         createAndAttach();
                                 });
                return;
            }

            createAndAttach();
        });

    return app.exec();
}

#include "main.moc"
