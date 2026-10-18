#include "shellkeelactions.h"

#include "appmodel.h"
#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "displaypolicycontroller.h"
#include "processtree.h"
#include "sessionstore.h"
#include "taskmodel.h"
#include "uistore.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>

namespace {

    QString compact(const QJsonObject &object) {
        return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
    }

    // Every argument the manifest declares is a bounded string.
    QString invalid(const QJsonObject &schema, const QJsonObject &args) {
        const QJsonObject properties = schema.value(QLatin1String("properties")).toObject();
        for (auto it = args.constBegin(); it != args.constEnd(); ++it) {
            const QJsonObject property = properties.value(it.key()).toObject();
            if (property.isEmpty())
                return QStringLiteral("unknown argument ") + it.key();
            const int maxLength = property.value(QLatin1String("maxLength")).toInt();
            if (!it->isString() || it->toString().size() > maxLength)
                return it.key() + QStringLiteral(" must be a string of at most ") +
                    QString::number(maxLength) + QStringLiteral(" characters");
        }
        const QJsonArray required = schema.value(QLatin1String("required")).toArray();
        for (const auto &name : required) {
            if (!args.contains(name.toString()))
                return QStringLiteral("missing argument ") + name.toString();
        }
        return {};
    }

} // namespace

ShellKeelActions::ShellKeelActions(AppModel *apps, TaskModel *tasks,
                                   AppLaunchService *launchService, AppLifecycleManager *lifecycle,
                                   UIStore *uiStore, SessionStore *session,
                                   DisplayPolicyController *display, QObject *parent)
    : QObject(parent)
    , m_apps(apps)
    , m_tasks(tasks)
    , m_launchService(launchService)
    , m_lifecycle(lifecycle)
    , m_uiStore(uiStore)
    , m_session(session)
    , m_display(display) {
    QFile file(QStringLiteral(":/keel/keel-actions.json"));
    m_manifest = file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    const QJsonArray tools =
        QJsonDocument::fromJson(m_manifest).object().value(QLatin1String("tools")).toArray();
    for (const auto &tool : tools)
        m_tools.insert(
            tool[QLatin1String("_meta")][QLatin1String("org.shipwright.keel/action")].toString(),
            tool.toObject());
}

bool ShellKeelActions::registerOnSessionBus() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    return bus.registerObject(QStringLiteral("/org/shipwright/Keel/Actions"), this,
                              QDBusConnection::ExportAllSlots) &&
        bus.registerService(QStringLiteral("org.marathonos.shell"));
}

// An app the shell runs, or any process it started.
bool ShellKeelActions::fromApp() const {
    const QDBusReply<uint> pid = connection().interface()->servicePid(message().service());
    if (!pid.isValid())
        return true;
    const qint64 caller = pid.value();
    const qint64 shell  = QCoreApplication::applicationPid();
    return !m_launchService->appIdForPid(caller).isEmpty() ||
        (caller != shell && isDescendantPid(caller, shell));
}

QString ShellKeelActions::fail(const QString &code, const QString &message) {
    sendErrorReply(QLatin1String("org.shipwright.Keel.Actions.Error.") + code, message);
    return {};
}

QString ShellKeelActions::Describe() {
    return QString::fromUtf8(m_manifest);
}

QString ShellKeelActions::Invoke(const QString &action, const QString &arguments,
                                 const QVariantMap &) {
    if (fromApp()) {
        sendErrorReply(QDBusError::AccessDenied, QStringLiteral("apps cannot drive the shell"));
        return {};
    }
    const QJsonObject tool = m_tools.value(action);
    if (tool.isEmpty())
        return fail(QStringLiteral("UnknownAction"), QStringLiteral("no action named ") + action);
    const QJsonDocument doc = QJsonDocument::fromJson(arguments.toUtf8());
    if (!doc.isObject())
        return fail(QStringLiteral("InvalidArguments"),
                    QStringLiteral("arguments must be a JSON object"));
    if (const QString why =
            invalid(tool.value(QLatin1String("inputSchema")).toObject(), doc.object());
        !why.isEmpty())
        return fail(QStringLiteral("InvalidArguments"), why);
    if (!tool[QLatin1String("annotations")][QLatin1String("readOnlyHint")].toBool() &&
        m_session->isLocked())
        return fail(QStringLiteral("NotAvailable"), QStringLiteral("the phone is locked"));
    qInfo() << "[ShellKeelActions]" << action << arguments;
    return run(action, doc.object());
}

QString ShellKeelActions::run(const QString &action, const QJsonObject &args) {
    const QString id = args.value(QLatin1String("id")).toString();
    if (action == QLatin1String("apps.list")) {
        QJsonArray apps;
        for (int i = 0; i < m_apps->count(); ++i) {
            const App *app = m_apps->getAppAtIndex(i);
            apps.append(QJsonObject{{QStringLiteral("id"), app->id()},
                                    {QStringLiteral("name"), app->name()}});
        }
        return compact({{QStringLiteral("result"), apps}});
    }
    if (action == QLatin1String("apps.running")) {
        QJsonArray open;
        for (int i = 0; i < m_tasks->rowCount(); ++i) {
            const QModelIndex row = m_tasks->index(i);
            open.append(
                QJsonObject{{QStringLiteral("id"), row.data(TaskModel::AppIdRole).toString()},
                            {QStringLiteral("name"), row.data(TaskModel::TitleRole).toString()}});
        }
        return compact({{QStringLiteral("result"), open}});
    }
    if (action == QLatin1String("shell.state")) {
        return compact({{QStringLiteral("locked"), m_session->isLocked()},
                        {QStringLiteral("screenOn"), m_display->screenOn()},
                        {QStringLiteral("foregroundApp"),
                         m_uiStore->appWindowOpen() ? m_uiStore->currentAppId() : QString()},
                        {QStringLiteral("quickSettingsOpen"), m_uiStore->quickSettingsOpen()}});
    }
    if (action == QLatin1String("app.launch")) {
        if (!m_apps->getApp(id))
            return fail(QStringLiteral("InvalidArguments"), QStringLiteral("no app ") + id);
        const QString route = args.value(QLatin1String("route")).toString();
        const bool ok = route.isEmpty() ? m_launchService->launchApp(id) :
                                          m_launchService->launchAppWithRoute(id, route, QString());
        return ok ? QStringLiteral("{}") :
                    fail(QStringLiteral("Failed"), id + QStringLiteral(" did not start"));
    }
    if (action == QLatin1String("app.close")) {
        const Task *task = m_tasks->getTaskByAppId(id);
        if (!task)
            return fail(QStringLiteral("InvalidArguments"), id + QStringLiteral(" is not open"));
        // As its switcher card closes it.
        if (task->appType() == QLatin1String("native") && task->surfaceId() >= 0) {
            const QString taskId = task->id();
            m_lifecycle->prepareClose(id);
            m_launchService->closeNativeApp(task->surfaceId());
            m_tasks->closeTask(taskId);
        } else {
            m_lifecycle->closeApp(id);
        }
        return QStringLiteral("{}");
    }
    if (action == QLatin1String("shell.home") || action == QLatin1String("shell.switcher")) {
        m_launchService->requestHome(action == QLatin1String("shell.switcher"));
        return QStringLiteral("{}");
    }
    if (action == QLatin1String("quicksettings.show") ||
        action == QLatin1String("quicksettings.hide")) {
        m_launchService->requestQuickSettings(action == QLatin1String("quicksettings.show") ? 1 :
                                                                                              0);
        return QStringLiteral("{}");
    }
    return fail(QStringLiteral("UnknownAction"), QStringLiteral("no action named ") + action);
}

QString ShellKeelActions::GetEntity(const QString &type, const QString &) {
    return fail(QStringLiteral("UnknownAction"), QStringLiteral("no entity type ") + type);
}

QString ShellKeelActions::FindEntities(const QString &type, const QString &, uint) {
    return fail(QStringLiteral("UnknownAction"), QStringLiteral("no entity type ") + type);
}

QString ShellKeelActions::GetContext() {
    return QStringLiteral("{}");
}
