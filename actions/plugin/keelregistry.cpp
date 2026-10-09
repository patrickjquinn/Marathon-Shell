// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keelregistry.h"

#include "keeladaptor.h"
#include "keelcall.h"
#include "keeldeclarations.h"
#include "keelnative.h"
#include "keelschema.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlEngine>
#include <QTimer>

#include <algorithm>

namespace {

QJsonArray sortedBy(const QJsonArray &array, const QString &key = QStringLiteral("name"))
{
    QList<QJsonValue> list(array.begin(), array.end());
    std::sort(list.begin(), list.end(), [&key](const QJsonValue &a, const QJsonValue &b) {
        return a.toObject().value(key).toString() < b.toObject().value(key).toString();
    });
    QJsonArray out;
    for (const QJsonValue &v : list)
        out.append(v);
    return out;
}

bool isHeadlessLaunch()
{
    if (qEnvironmentVariable("KEEL_ACTIONS_HEADLESS") == QLatin1String("1"))
        return true;
    return QCoreApplication::instance() && QCoreApplication::arguments().contains(QStringLiteral("--keel-actions"));
}

} // namespace

KeelActionRegistry *KeelActionRegistry::instance()
{
    static KeelActionRegistry *registry = nullptr;
    if (!registry) {
        registry = new KeelActionRegistry(QCoreApplication::instance());
        // Lives with the application; QML must never delete it.
        QQmlEngine::setObjectOwnership(registry, QQmlEngine::CppOwnership);
    }
    return registry;
}

KeelActionRegistry *KeelActionRegistry::create(QQmlEngine *, QJSEngine *)
{
    return instance();
}

KeelActionRegistry::KeelActionRegistry(QObject *parent)
    : QObject(parent)
    , m_headless(isHeadlessLaunch())
{
    loadManifest();
    trackApplicationState();
}

void KeelActionRegistry::loadManifest()
{
    const QString path = qEnvironmentVariable("KEEL_ACTIONS_MANIFEST");
    if (path.isEmpty()) {
        // The manifest compiled into the app (keel::manifest!(), keel_actions.c).
        const QJsonObject compiled = KeelNative::table().manifest;
        if (!compiled.isEmpty())
            setManifest(compiled);
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning().noquote() << "Keel.Actions: cannot read KEEL_ACTIONS_MANIFEST" << path;
        return;
    }
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (!doc.isObject()) {
        qWarning().noquote() << "Keel.Actions:" << path << "is not a JSON object:" << error.errorString();
        return;
    }
    setManifest(doc.object());
}

void KeelActionRegistry::setManifest(const QJsonObject &manifest)
{
    m_manifest = manifest;
    const QString id = manifest.value(QLatin1String("appId")).toString();
    if (!id.isEmpty() && id != m_appId) {
        m_appId = id;
        Q_EMIT appIdChanged();
    }
}

void KeelActionRegistry::trackApplicationState()
{
    // Test hook: no window system decides the foreground in a test run.
    if (qEnvironmentVariable("KEEL_ACTIONS_FOREGROUND") == QLatin1String("1")) {
        m_foreground = true;
        return;
    }
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (!app)
        return;
    const auto update = [this](Qt::ApplicationState state) {
        const bool foreground = state == Qt::ApplicationActive;
        if (m_foreground && !foreground)
            m_sinceBackground.start();
        m_foreground = foreground;
    };
    update(QGuiApplication::applicationState());
    connect(app, &QGuiApplication::applicationStateChanged, this, update);
}

QString KeelActionRegistry::appId() const
{
    if (!m_appId.isEmpty())
        return m_appId;
    QString fromEnv = qEnvironmentVariable("KEEL_ACTIONS_APP_ID");
    if (!fromEnv.isEmpty())
        return fromEnv;
    // Sailjail's convention: OrganizationName.ApplicationName.
    const QString org = QCoreApplication::organizationName();
    const QString name = QCoreApplication::applicationName();
    return org.isEmpty() ? name : org + QLatin1Char('.') + name;
}

void KeelActionRegistry::setAppId(const QString &appId)
{
    if (m_appId == appId)
        return;
    m_appId = appId;
    Q_EMIT appIdChanged();
}

QJsonObject KeelActionRegistry::describe() const
{
    const QString app = appId();
    QJsonArray tools;
    for (const QPointer<KeelAction> &action : m_actions) {
        if (action)
            tools.append(action->tool(app));
    }
    QJsonArray entities;
    for (const QPointer<KeelEntity> &entity : m_entities) {
        if (!entity)
            continue;
        tools.append(entity->findTool(app));
        entities.append(entity->manifestEntry(app));
    }
    QJsonArray prompts;
    for (const QPointer<KeelShortcut> &shortcut : m_shortcuts) {
        if (shortcut)
            prompts.append(shortcut->prompt(app));
    }
    QJsonObject manifest{
        {QStringLiteral("version"), 1},
        {QStringLiteral("appId"), app},
        {QStringLiteral("tools"), sortedBy(tools)},
        {QStringLiteral("entities"), sortedBy(entities, QStringLiteral("type"))},
        {QStringLiteral("prompts"), sortedBy(prompts)},
    };
    const bool hasContext = std::any_of(m_contexts.cbegin(), m_contexts.cend(),
                                        [](const QPointer<KeelContext> &c) { return !c.isNull(); });
    if (hasContext) {
        manifest.insert(QStringLiteral("context"), QJsonObject{
            {QStringLiteral("uri"), QStringLiteral("keel://") + app + QStringLiteral("/context")},
        });
    }
    return manifest;
}

QJsonObject KeelActionRegistry::effectiveManifest() const
{
    return m_manifest.isEmpty() ? describe() : m_manifest;
}

QJsonObject KeelActionRegistry::tool(const QString &action) const
{
    const QJsonObject manifest = effectiveManifest();
    const QString name = manifest.value(QLatin1String("appId")).toString() + QLatin1Char('/') + action;
    for (const auto &t : manifest.value(QLatin1String("tools")).toArray()) {
        if (t.toObject().value(QLatin1String("name")).toString() == name)
            return t.toObject();
    }
    return {};
}

bool KeelActionRegistry::declared(const QString &action) const
{
    return !m_manifest.isEmpty() && !tool(action).isEmpty();
}

KeelCall *KeelActionRegistry::invoke(const QString &action, const QVariantMap &arguments, const QVariantMap &options)
{
    auto *call = new KeelCall(action, arguments, options.value(QStringLiteral("userInitiated")).toBool());
    start(call, m_actions.value(action));
    return call;
}

void KeelActionRegistry::start(KeelCall *call, KeelAction *target)
{
    Q_EMIT activity();
    connect(call, &KeelCall::completed, this, &KeelActionRegistry::activity);

    QJsonObject tool = this->tool(call->action());
    if (tool.isEmpty() && target)
        tool = target->tool(appId());
    if (tool.isEmpty()) {
        call->fail(KeelCall::UnknownAction, QStringLiteral("no action named ") + call->action());
        return;
    }
    if (tool.value(QLatin1String("_meta")).toObject().contains(KeelSchema::metaKey("find"))) {
        call->fail(KeelCall::UnknownAction, QStringLiteral("entity searches go through FindEntities"));
        return;
    }
    const QJsonValue args = KeelCall::toJson(call->arguments());
    const QString invalid = KeelSchema::validate(tool.value(QLatin1String("inputSchema")).toObject(), args);
    if (!invalid.isEmpty()) {
        call->fail(KeelCall::InvalidArguments, invalid);
        return;
    }

    const QString kind = tool.value(QLatin1String("_meta")).toObject().value(KeelSchema::metaKey("result")).toString();
    const QJsonObject output = tool.value(QLatin1String("outputSchema")).toObject();
    call->setCheck([kind, output](QJsonValue &value, QString &) {
        if (kind == QLatin1String("none")) {
            value = QJsonObject();
            return QString();
        }
        if (kind == QLatin1String("wrapped"))
            value = QJsonObject{{QStringLiteral("result"), value}};
        return KeelSchema::validate(output, value);
    });

    if (target) {
        target->dispatch(call);
        return;
    }
    if (startNative(call))
        return;
    // Declared but not registered yet: activation can run before the QML
    // that declares the action has loaded.
    call->startTimer(RegistrationWaitMs);
    m_pending.append(call);
}

bool KeelActionRegistry::startNative(KeelCall *call)
{
    const QJsonObject tool = this->tool(call->action());
    const int timeout = tool.value(QLatin1String("_meta")).toObject().value(KeelSchema::metaKey("timeoutMs")).toInt(25000);
    const QPointer<KeelCall> guarded(call);
    const bool started = KeelNative::invoke(call->action(), KeelCall::toJson(call->arguments()), this,
                                            [guarded](bool ok, const QJsonValue &value) {
                                                if (!guarded)
                                                    return;
                                                if (ok)
                                                    guarded->replyJson(value);
                                                else
                                                    guarded->fail(value.toObject().value(QLatin1String("code")).toString(),
                                                                  value.toObject().value(QLatin1String("message")).toString());
                                            });
    if (started)
        call->startTimer(timeout);
    return started;
}

QJsonObject KeelActionRegistry::entityEntry(const QString &type) const
{
    for (const auto &e : effectiveManifest().value(QLatin1String("entities")).toArray()) {
        if (e.toObject().value(QLatin1String("type")).toString() == type)
            return e.toObject();
    }
    return {};
}

void KeelActionRegistry::serve()
{
    if (m_serving)
        return;
    if (m_manifest.isEmpty() && qEnvironmentVariable("KEEL_ACTIONS_DBUS") != QLatin1String("1"))
        return;
    m_serving = true;
    auto *adaptor = new KeelActionsAdaptor(this);
    adaptor->start();
}

void KeelActionRegistry::flushPending(const QString &action)
{
    KeelAction *target = m_actions.value(action);
    if (!target)
        return;
    const QList<QPointer<KeelCall>> pending = m_pending;
    m_pending.clear();
    for (const QPointer<KeelCall> &call : pending) {
        if (!call || call->isFinished())
            continue;
        if (call->action() == action)
            target->dispatch(call);
        else
            m_pending.append(call);
    }
}

KeelCall *KeelActionRegistry::getEntity(const QString &type, const QString &id)
{
    Q_EMIT activity();
    auto *call = new KeelCall(type, QVariantMap{{QStringLiteral("id"), id}}, false);
    connect(call, &KeelCall::completed, this, &KeelActionRegistry::activity);
    KeelEntity *entity = m_entities.value(type);
    const QJsonObject entry = entityEntry(type);
    if (id.isEmpty() || id.size() > KeelSchema::IdMaxLength || id.contains(QLatin1Char('/'))) {
        call->fail(KeelCall::InvalidArguments, QStringLiteral("an id has 1 to 256 characters and no '/'"));
    } else if (entity) {
        entity->dispatchLookup(call, id);
    } else if (!entry.isEmpty() && KeelNative::table().entities.contains(type)) {
        const QJsonObject schema = entry.value(QLatin1String("schema")).toObject();
        const QString uri = QStringLiteral("keel://") + appId() + QLatin1Char('/') + type + QLatin1Char('/') + id;
        call->setCheck([schema, id, uri](QJsonValue &value, QString &code) {
            if (!value.isObject()) {
                code = KeelCall::NotAvailable;
                return QStringLiteral("no such item");
            }
            QJsonObject object = value.toObject();
            if (!object.contains(QLatin1String("id")))
                object.insert(QStringLiteral("id"), id);
            object.insert(QStringLiteral("uri"), uri);
            value = object;
            return KeelSchema::validate(schema, value);
        });
        call->startTimer(25000);
        const QPointer<KeelCall> guarded(call);
        KeelNative::getEntity(type, id, this, [guarded](bool ok, const QJsonValue &value) {
            if (guarded && ok)
                guarded->replyJson(value);
            else if (guarded)
                guarded->fail(value.toObject().value(QLatin1String("code")).toString(),
                              value.toObject().value(QLatin1String("message")).toString());
        });
    } else {
        call->fail(KeelCall::UnknownAction, QStringLiteral("no entity type ") + type);
    }
    return call;
}

KeelCall *KeelActionRegistry::findEntities(const QString &type, const QString &query, int limit)
{
    Q_EMIT activity();
    auto *call = new KeelCall(type, QVariantMap{{QStringLiteral("query"), query}, {QStringLiteral("limit"), limit}}, false);
    connect(call, &KeelCall::completed, this, &KeelActionRegistry::activity);
    KeelEntity *entity = m_entities.value(type);
    const int bounded = std::clamp(limit, 1, KeelSchema::FindLimitMax);
    if (query.size() > KeelSchema::FindQueryMaxLength) {
        call->fail(KeelCall::InvalidArguments, QStringLiteral("the query is longer than 256 characters"));
    } else if (entity) {
        entity->dispatchSearch(call, query, bounded);
    } else if (!entityEntry(type).isEmpty() && KeelNative::table().entities.contains(type)) {
        const QJsonObject output = tool(type + QStringLiteral(".find")).value(QLatin1String("outputSchema")).toObject();
        call->setCheck(KeelEntity::findCheck(output, QStringLiteral("keel://") + appId() + QLatin1Char('/') + type
                                                         + QLatin1Char('/'), bounded));
        call->startTimer(25000);
        const QPointer<KeelCall> guarded(call);
        KeelNative::findEntities(type, query, bounded, this, [guarded](bool ok, const QJsonValue &value) {
            if (guarded && ok)
                guarded->replyJson(value);
            else if (guarded)
                guarded->fail(value.toObject().value(QLatin1String("code")).toString(),
                              value.toObject().value(QLatin1String("message")).toString());
        });
    } else {
        call->fail(KeelCall::UnknownAction, QStringLiteral("no entity type ") + type);
    }
    return call;
}

QJsonObject KeelActionRegistry::context() const
{
    const bool recent = m_foreground
        || (m_sinceBackground.isValid() && m_sinceBackground.elapsed() < ContextForegroundMs);
    if (!recent)
        return {};
    // The most recently registered active context: the page on top.
    for (auto it = m_contexts.crbegin(); it != m_contexts.crend(); ++it) {
        if (*it && (*it)->isActive())
            return (*it)->snapshot(appId());
    }
    return {};
}

void KeelActionRegistry::addAction(KeelAction *action)
{
    const QString name = action->name();
    if (name.isEmpty()) {
        qWarning("Keel.Actions: a KeelAction without a name is ignored");
        return;
    }
    if (m_actions.value(name) && m_actions.value(name) != action) {
        qWarning().noquote() << "Keel.Actions: action" << name << "is declared twice; the first one is used";
        return;
    }
    m_actions.insert(name, action);
    flushPending(name);
}

void KeelActionRegistry::removeAction(KeelAction *action)
{
    if (m_actions.value(action->name()) == action)
        m_actions.remove(action->name());
}

void KeelActionRegistry::addEntity(KeelEntity *entity)
{
    if (m_entities.value(entity->type()) && m_entities.value(entity->type()) != entity) {
        qWarning().noquote() << "Keel.Actions: entity type" << entity->type() << "is declared twice; the first one is used";
        return;
    }
    m_entities.insert(entity->type(), entity);
}

void KeelActionRegistry::removeEntity(KeelEntity *entity)
{
    if (m_entities.value(entity->type()) == entity)
        m_entities.remove(entity->type());
}

void KeelActionRegistry::addContext(KeelContext *context)
{
    m_contexts.removeAll(nullptr);
    m_contexts.append(context);
}

void KeelActionRegistry::removeContext(KeelContext *context)
{
    m_contexts.removeAll(context);
}

void KeelActionRegistry::addShortcut(KeelShortcut *shortcut)
{
    m_shortcuts.removeAll(nullptr);
    m_shortcuts.append(shortcut);
}

void KeelActionRegistry::removeShortcut(KeelShortcut *shortcut)
{
    m_shortcuts.removeAll(shortcut);
}
