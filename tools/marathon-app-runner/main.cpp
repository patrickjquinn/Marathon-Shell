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
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusError>

#include <memory>

#include "marathonappregistry.h"
#include "marathonappscanner.h"

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
    QString tmpRoot = tmpBase + QString("/shell-qmldir-%1").arg(QCoreApplication::applicationPid());
    const QString tmpModuleDir = QDir(tmpRoot).filePath(moduleRelDir);

    QDir().mkpath(tmpModuleDir);

    QString           patched;
    QTextStream       out(&patched);

    const QStringList lines = qmldirText.split('\n');
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        if (line.startsWith("prefer "))
            continue;

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
    parser.process(app);

    const QString appId = parser.value(appIdOpt).trimmed();
    if (appId.isEmpty()) {
        qCritical() << "[marathon-app-runner] Missing --app-id";
        return 2;
    }

    QGuiApplication::setDesktopFileName(appId);

    MarathonAppRegistry registry;
    MarathonAppScanner  scanner(&registry);
    scanner.scanApplications();

    MarathonAppRegistry::AppInfo *info = registry.getAppInfo(appId);
    if (!info) {
        qCritical() << "[marathon-app-runner] App not found in registry:" << appId;
        return 3;
    }

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setTitle(info->name);

    view.setColor(Qt::transparent);

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

    const QByteArray shellQmlEnv = qgetenv("MARATHON_SHELL_QML_IMPORT_PATH").trimmed();
    if (!shellQmlEnv.isEmpty()) {
        const QString p = QString::fromLocal8Bit(shellQmlEnv);
        if (QDir(p).exists()) {
            const QString patchedRoot = createPatchedQmldirWithoutPrefer(p, "MarathonOS/Shell");
            if (!patchedRoot.isEmpty())
                engine->addImportPath(patchedRoot);
            else
                engine->addImportPath(p);
        }
    } else {
        const QDir        binDir(QCoreApplication::applicationDirPath());

        const QString     p1         = binDir.filePath("../../shell/qml");
        const QString     p2         = binDir.filePath("../shell/qml");
        const QString     p3         = binDir.filePath("shell/qml");
        const QString     p4         = "/usr/local/lib/qt6/qml";
        const QString     p5         = "/usr/lib/qt6/qml";
        const QString     p6         = "/usr/lib64/qt6/qml";
        const QStringList candidates = {p1, p2, p3, p4, p5, p6};
        for (const QString &cand : candidates) {
            if (!QDir(cand).exists())
                continue;

            const QString patchedRoot = createPatchedQmldirWithoutPrefer(cand, "MarathonOS/Shell");
            if (!patchedRoot.isEmpty()) {

                engine->addImportPath(patchedRoot);
            } else {
                engine->addImportPath(cand);
            }
        }
    }

    engine->addImportPath("qrc:/");
    engine->addImportPath(":/");

    auto      *ctx = view.rootContext();

    const auto hasPerm = [&](const QString &perm) -> bool {
        return std::find(info->permissions.begin(), info->permissions.end(), perm) !=
            info->permissions.end();
    };

    ctx->setContextProperty("PermissionManager", new PermissionClient(&app));
    ctx->setContextProperty("ContactsManager", new ContactsClient(&app));
    ctx->setContextProperty("CallHistoryManager", new CallHistoryClient(&app));
    ctx->setContextProperty("TelephonyService", new TelephonyClient(appId, &app));
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
    }

    if (hasPerm("network"))
        ctx->setContextProperty("NetworkManagerCpp", new NetworkClient(appId, &app));

    ctx->setContextProperty("NavigationService", new NavigationClient(&app));
    ctx->setContextProperty("HapticService", new HapticClient(&app));
    auto *notificationClient = new NotificationClient(appId, &app);
    ctx->setContextProperty("NativeNotificationService", notificationClient);
    ctx->setContextProperty("SensorService", new SensorClient(&app));
    ctx->setContextProperty("LocationService", new LocationClient(&app));
    ctx->setContextProperty("AlarmService", new AlarmClient(&app));

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
