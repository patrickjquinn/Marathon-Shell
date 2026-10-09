// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Schema mapping (identical in keel/actions/schema, the Rust generator):
//
//   string   {type: string, maxLength (default 4096), minLength, pattern,
//             format, enum}
//   integer  {type: integer, minimum, maximum (default the 32-bit range), enum}
//   number   {type: number, minimum, maximum, enum}
//   boolean  {type: boolean}
//   entity   {$ref: "#/$defs/<app-id>.<type>"}; the definition is a string
//            with the keel://<app-id>/<type>/<id> pattern and x-keel-entity
//   object   {type: object, properties, required, additionalProperties: false}
//            from `fields` (required strings) and `properties`
//   array    {type: array, maxItems (default 100), items: the itemType's
//            schema built from the same declaration}
// plus title, description and default where declared. Entity properties
// carry x-keel-summarisable / x-keel-indexable.

#include "keeldeclarations.h"

#include "keelcall.h"
#include "keelregistry.h"
#include "keelschema.h"

#include <QDebug>
#include <QJsonArray>
#include <QQmlEngine>
#include <QQmlError>

namespace {

// Runs `emitter` (a signal emission into QML handlers) and fails `call` if a
// handler threw: QML reports the exception as a warning and the handler
// would otherwise leave the call unanswered until its timeout.
template <typename F>
void emitGuarded(QObject *declaration, KeelCall *call, F emitter)
{
    QString error;
    QMetaObject::Connection connection;
    if (QQmlEngine *engine = qmlEngine(declaration)) {
        connection = QObject::connect(engine, &QQmlEngine::warnings, call, [&error](const QList<QQmlError> &warnings) {
            if (error.isEmpty() && !warnings.isEmpty())
                error = warnings.first().toString();
        });
    }
    emitter();
    QObject::disconnect(connection);
    if (!error.isEmpty() && !call->isFinished())
        call->fail(KeelCall::Failed, QStringLiteral("the handler failed: ") + error);
}

template <typename T>
QQmlListProperty<T> listOf(QObject *owner, QList<T *> *list)
{
    return QQmlListProperty<T>(owner, list);
}

QJsonObject withDefs(QJsonObject schema, const QJsonObject &defs)
{
    if (!defs.isEmpty())
        schema.insert(QStringLiteral("$defs"), defs);
    return schema;
}

QString registryAppId()
{
    return KeelActionRegistry::instance()->appId();
}

} // namespace

// ---------------------------------------------------------------------------
// KeelParam, KeelResult
// ---------------------------------------------------------------------------

KeelParam::KeelParam(QObject *parent)
    : QObject(parent)
{
}

QQmlListProperty<KeelParam> KeelParam::properties()
{
    return listOf(this, &m_properties);
}

QJsonObject KeelParam::objectSchema(const QString &appId, QJsonObject &defs) const
{
    QJsonObject properties;
    QStringList required;
    for (const QString &field : m_fields) {
        properties.insert(field, QJsonObject{{QStringLiteral("type"), QStringLiteral("string")},
                                             {QStringLiteral("maxLength"), KeelSchema::DefaultMaxLength}});
        required << field;
    }
    for (const KeelParam *p : m_properties) {
        properties.insert(p->m_name, p->schema(appId, defs));
        if (p->m_required)
            required << p->m_name;
    }
    return KeelSchema::object(properties, required);
}

QJsonObject KeelParam::scalarSchema(const QString &type, const QString &appId, QJsonObject &defs) const
{
    QJsonObject s;
    if (type == QLatin1String("entity")) {
        if (m_entity.isEmpty())
            qWarning().noquote() << "KeelParam" << m_name << ": type entity needs `entity`";
        return KeelSchema::entityRef(KeelSchema::qualifiedEntity(m_entity, appId), defs);
    }
    if (type == QLatin1String("object"))
        return objectSchema(appId, defs);
    if (type == QLatin1String("integer")) {
        s.insert(QStringLiteral("type"), type);
        s.insert(QStringLiteral("minimum"), m_minimum.isValid() ? m_minimum.toLongLong() : KeelSchema::DefaultIntMin);
        s.insert(QStringLiteral("maximum"), m_maximum.isValid() ? m_maximum.toLongLong() : KeelSchema::DefaultIntMax);
    } else if (type == QLatin1String("number")) {
        s.insert(QStringLiteral("type"), type);
        if (m_minimum.isValid())
            s.insert(QStringLiteral("minimum"), m_minimum.toDouble());
        if (m_maximum.isValid())
            s.insert(QStringLiteral("maximum"), m_maximum.toDouble());
    } else if (type == QLatin1String("boolean")) {
        s.insert(QStringLiteral("type"), type);
    } else {
        if (type != QLatin1String("string"))
            qWarning().noquote() << "KeelParam" << m_name << ": unknown type" << type << "(treated as string)";
        s.insert(QStringLiteral("type"), QStringLiteral("string"));
        s.insert(QStringLiteral("maxLength"), m_maxLength >= 0 ? m_maxLength : KeelSchema::DefaultMaxLength);
        if (m_minLength > 0)
            s.insert(QStringLiteral("minLength"), m_minLength);
        if (!m_pattern.isEmpty())
            s.insert(QStringLiteral("pattern"), m_pattern);
        if (!m_format.isEmpty())
            s.insert(QStringLiteral("format"), m_format);
    }
    if (!m_values.isEmpty())
        s.insert(QStringLiteral("enum"), QJsonArray::fromVariantList(m_values));
    return s;
}

QJsonObject KeelParam::schema(const QString &appId, QJsonObject &defs) const
{
    QJsonObject s;
    if (m_type == QLatin1String("array")) {
        s.insert(QStringLiteral("type"), QStringLiteral("array"));
        s.insert(QStringLiteral("maxItems"), m_maxItems >= 0 ? m_maxItems : KeelSchema::DefaultMaxItems);
        s.insert(QStringLiteral("items"),
                 scalarSchema(m_itemType.isEmpty() ? QStringLiteral("string") : m_itemType, appId, defs));
    } else {
        s = scalarSchema(m_type, appId, defs);
    }
    if (!m_title.isEmpty())
        s.insert(QStringLiteral("title"), m_title);
    if (!m_description.isEmpty())
        s.insert(QStringLiteral("description"), m_description);
    if (m_defaultValue.isValid())
        s.insert(QStringLiteral("default"), KeelCall::toJson(m_defaultValue));
    if (m_summarisable)
        s.insert(QStringLiteral("x-keel-summarisable"), true);
    if (m_indexable)
        s.insert(QStringLiteral("x-keel-indexable"), true);
    return s;
}

KeelResult::KeelResult(QObject *parent)
    : KeelParam(parent)
{
    m_type = QStringLiteral("none");
}

// ---------------------------------------------------------------------------
// KeelAction
// ---------------------------------------------------------------------------

KeelAction::KeelAction(QObject *parent)
    : QObject(parent)
{
}

KeelAction::~KeelAction()
{
    if (m_registered)
        KeelActionRegistry::instance()->removeAction(this);
}

void KeelAction::componentComplete()
{
    KeelActionRegistry::instance()->addAction(this);
    m_registered = true;
}

QQmlListProperty<KeelParam> KeelAction::parameters()
{
    return listOf(this, &m_parameters);
}

bool KeelAction::hasResult() const
{
    return m_returns && m_returns->type() != QLatin1String("none");
}

QJsonObject KeelAction::tool(const QString &appId) const
{
    QJsonObject inputDefs;
    QJsonObject properties;
    QStringList required;
    for (const KeelParam *p : m_parameters) {
        properties.insert(p->name(), p->schema(appId, inputDefs));
        if (p->isRequired())
            required << p->name();
    }

    QString resultKind = QStringLiteral("none");
    QJsonObject tool{
        {QStringLiteral("name"), appId + QLatin1Char('/') + m_name},
        {QStringLiteral("description"), m_description},
        {QStringLiteral("inputSchema"), withDefs(KeelSchema::object(properties, required), inputDefs)},
        {QStringLiteral("annotations"), QJsonObject{
             {QStringLiteral("readOnlyHint"), m_readOnly},
             {QStringLiteral("destructiveHint"), m_destructive},
             {QStringLiteral("idempotentHint"), m_idempotent},
             {QStringLiteral("openWorldHint"), m_openWorld},
         }},
    };
    if (!m_title.isEmpty())
        tool.insert(QStringLiteral("title"), m_title);
    if (hasResult()) {
        QJsonObject outputDefs;
        QJsonObject output = m_returns->schema(appId, outputDefs);
        if (m_returns->type() == QLatin1String("object")) {
            resultKind = QStringLiteral("object");
        } else {
            output = KeelSchema::wrapResult(output);
            resultKind = QStringLiteral("wrapped");
        }
        tool.insert(QStringLiteral("outputSchema"), withDefs(output, outputDefs));
    }
    QJsonObject meta{
        {KeelSchema::metaKey("action"), m_name},
        {KeelSchema::metaKey("confirm"), m_confirm},
        {KeelSchema::metaKey("sensitive"), m_sensitive},
        {KeelSchema::metaKey("result"), resultKind},
        {KeelSchema::metaKey("timeoutMs"), m_timeout},
    };
    if (!m_notDestructiveBecause.isEmpty())
        meta.insert(KeelSchema::metaKey("notDestructiveBecause"), m_notDestructiveBecause);
    if (m_untrusted)
        meta.insert(KeelSchema::metaKey("untrusted"), true);
    tool.insert(QStringLiteral("_meta"), meta);
    return tool;
}

KeelCall *KeelAction::invoke(const QVariantMap &arguments)
{
    auto *call = new KeelCall(m_name, arguments, true);
    KeelActionRegistry::instance()->start(call, this);
    return call;
}

void KeelAction::dispatch(KeelCall *call)
{
    if (!m_enabled) {
        call->fail(KeelCall::NotAvailable, QStringLiteral("the action is not available now"));
        return;
    }
    call->startTimer(m_timeout);
    emitGuarded(this, call, [this, call]() { Q_EMIT invoked(call->arguments(), call); });
    if (!hasResult())
        call->replyIfPending(QJsonObject());
}

// ---------------------------------------------------------------------------
// KeelEntity
// ---------------------------------------------------------------------------

KeelEntity::KeelEntity(QObject *parent)
    : QObject(parent)
{
}

KeelEntity::~KeelEntity()
{
    if (m_registered)
        KeelActionRegistry::instance()->removeEntity(this);
}

void KeelEntity::componentComplete()
{
    KeelActionRegistry::instance()->addEntity(this);
    m_registered = true;
}

QQmlListProperty<KeelParam> KeelEntity::properties()
{
    return listOf(this, &m_properties);
}

QString KeelEntity::uri(const QString &id) const
{
    return QStringLiteral("keel://") + registryAppId() + QLatin1Char('/') + m_type + QLatin1Char('/') + id;
}

QJsonObject KeelEntity::entitySchema(const QString &appId, QJsonObject &defs, bool summaryOnly) const
{
    QJsonObject properties{
        {QStringLiteral("uri"), KeelSchema::entityRef(appId + QLatin1Char('/') + m_type, defs)},
        {QStringLiteral("id"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")},
                                           {QStringLiteral("maxLength"), KeelSchema::IdMaxLength}}},
        {QStringLiteral("title"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")},
                                              {QStringLiteral("maxLength"), KeelSchema::TitleMaxLength}}},
    };
    QStringList required{QStringLiteral("uri"), QStringLiteral("id"), QStringLiteral("title")};
    for (const KeelParam *p : m_properties) {
        if (summaryOnly && !p->summarisable())
            continue;
        properties.insert(p->name(), p->schema(appId, defs));
        if (p->isRequired())
            required << p->name();
    }
    return KeelSchema::object(properties, required);
}

QJsonObject KeelEntity::schema(const QString &appId, QJsonObject &defs) const
{
    return entitySchema(appId, defs, false);
}

QJsonObject KeelEntity::summarySchema(const QString &appId, QJsonObject &defs) const
{
    return entitySchema(appId, defs, true);
}

QJsonObject KeelEntity::findTool(const QString &appId) const
{
    const QString what = m_title.isEmpty() ? m_type : m_title;
    QJsonObject defs;
    QJsonObject items{
        {QStringLiteral("type"), QStringLiteral("array")},
        {QStringLiteral("maxItems"), KeelSchema::FindLimitMax},
        {QStringLiteral("items"), summarySchema(appId, defs)},
    };
    const QJsonObject input = KeelSchema::object(
        QJsonObject{
            {QStringLiteral("query"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")},
                                                  {QStringLiteral("maxLength"), KeelSchema::FindQueryMaxLength},
                                                  {QStringLiteral("description"), QStringLiteral("Text to look for; empty for the most recent.")}}},
            {QStringLiteral("limit"), QJsonObject{{QStringLiteral("type"), QStringLiteral("integer")},
                                                  {QStringLiteral("minimum"), 1},
                                                  {QStringLiteral("maximum"), KeelSchema::FindLimitMax},
                                                  {QStringLiteral("default"), 10}}},
        },
        {QStringLiteral("query")});
    QString description = QStringLiteral("Find %1 items by text. Returns references (uri, id, title) for later steps.").arg(what);
    if (!m_description.isEmpty())
        description += QLatin1Char(' ') + m_description;
    return QJsonObject{
        {QStringLiteral("name"), appId + QLatin1Char('/') + m_type + QStringLiteral(".find")},
        {QStringLiteral("title"), QStringLiteral("Find ") + what},
        {QStringLiteral("description"), description},
        {QStringLiteral("inputSchema"), input},
        {QStringLiteral("outputSchema"),
         withDefs(KeelSchema::object(QJsonObject{{QStringLiteral("items"), items}}, {QStringLiteral("items")}), defs)},
        {QStringLiteral("annotations"), QJsonObject{
             {QStringLiteral("readOnlyHint"), true},
             {QStringLiteral("destructiveHint"), false},
             {QStringLiteral("idempotentHint"), true},
             {QStringLiteral("openWorldHint"), false},
         }},
        {QStringLiteral("_meta"), QJsonObject{
             {KeelSchema::metaKey("find"), m_type},
             {KeelSchema::metaKey("confirm"), false},
             {KeelSchema::metaKey("sensitive"), false},
             {KeelSchema::metaKey("result"), QStringLiteral("object")},
             {KeelSchema::metaKey("timeoutMs"), 25000},
         }},
    };
}

QJsonObject KeelEntity::manifestEntry(const QString &appId) const
{
    QJsonObject defs;
    QJsonObject entry{
        {QStringLiteral("type"), m_type},
        {QStringLiteral("title"), m_title.isEmpty() ? m_type : m_title},
        {QStringLiteral("description"), m_description},
        {QStringLiteral("uriTemplate"), QStringLiteral("keel://") + appId + QLatin1Char('/') + m_type + QStringLiteral("/{id}")},
        {QStringLiteral("findTool"), appId + QLatin1Char('/') + m_type + QStringLiteral(".find")},
    };
    const QJsonObject s = schema(appId, defs);
    entry.insert(QStringLiteral("schema"), withDefs(s, defs));
    return entry;
}

KeelCall *KeelEntity::lookup(const QString &id)
{
    return KeelActionRegistry::instance()->getEntity(m_type, id);
}

KeelCall *KeelEntity::search(const QString &query, int limit)
{
    return KeelActionRegistry::instance()->findEntities(m_type, query, limit);
}

void KeelEntity::dispatchLookup(KeelCall *call, const QString &id)
{
    const QString appId = registryAppId();
    QJsonObject defs;
    const QJsonObject s = withDefs(schema(appId, defs), defs);
    const QString entityUri = uri(id);
    call->setCheck([s, id, entityUri](QJsonValue &value, QString &code) {
        if (value.isNull() || value.isUndefined()) {
            code = KeelCall::NotAvailable;
            return QStringLiteral("no such item");
        }
        if (!value.isObject())
            return QStringLiteral("an entity must be an object");
        QJsonObject object = value.toObject();
        if (!object.contains(QLatin1String("id")))
            object.insert(QStringLiteral("id"), id);
        object.insert(QStringLiteral("uri"), entityUri);
        value = object;
        return KeelSchema::validate(s, value);
    });
    call->startTimer(25000);
    emitGuarded(this, call, [this, call, &id]() { Q_EMIT resolve(id, call); });
}

std::function<QString(QJsonValue &, QString &)> KeelEntity::findCheck(const QJsonObject &output, const QString &prefix, int limit)
{
    const QJsonObject itemProperties = output.value(QLatin1String("properties")).toObject()
                                           .value(QLatin1String("items")).toObject()
                                           .value(QLatin1String("items")).toObject()
                                           .value(QLatin1String("properties")).toObject();
    return [output, itemProperties, prefix, limit](QJsonValue &value, QString &) {
        QJsonArray in;
        if (value.isArray())
            in = value.toArray();
        else if (value.isObject() && value.toObject().value(QLatin1String("items")).isArray())
            in = value.toObject().value(QLatin1String("items")).toArray();
        else if (!value.isNull())
            return QStringLiteral("find must answer a list of entities");
        QJsonArray items;
        for (const auto &v : std::as_const(in)) {
            if (items.size() >= limit)
                break;
            QJsonObject item;
            const QJsonObject source = v.toObject();
            // Only what a summary may carry: uri, id, title and the
            // summarisable properties.
            for (auto it = source.constBegin(); it != source.constEnd(); ++it) {
                if (itemProperties.contains(it.key()))
                    item.insert(it.key(), it.value());
            }
            item.insert(QStringLiteral("uri"), prefix + item.value(QLatin1String("id")).toString());
            items.append(item);
        }
        value = QJsonObject{{QStringLiteral("items"), items}};
        return KeelSchema::validate(output, value);
    };
}

void KeelEntity::dispatchSearch(KeelCall *call, const QString &query, int limit)
{
    const QString appId = registryAppId();
    const QJsonObject output = findTool(appId).value(QLatin1String("outputSchema")).toObject();
    call->setCheck(findCheck(output, QStringLiteral("keel://") + appId + QLatin1Char('/') + m_type + QLatin1Char('/'),
                             limit));
    call->startTimer(25000);
    emitGuarded(this, call, [this, call, &query, limit]() { Q_EMIT find(query, limit, call); });
}

// ---------------------------------------------------------------------------
// KeelContext
// ---------------------------------------------------------------------------

KeelContext::KeelContext(QObject *parent)
    : QObject(parent)
{
}

KeelContext::~KeelContext()
{
    if (m_registered)
        KeelActionRegistry::instance()->removeContext(this);
}

void KeelContext::componentComplete()
{
    KeelActionRegistry::instance()->addContext(this);
    m_registered = true;
}

QJsonObject KeelContext::snapshot(const QString &appId) const
{
    QJsonObject s{{QStringLiteral("app"), appId}};
    if (!m_purpose.isEmpty())
        s.insert(QStringLiteral("purpose"), m_purpose.left(KeelSchema::ContextPurposeMaxLength));
    if (m_entity.startsWith(QLatin1String("keel://")))
        s.insert(QStringLiteral("entity"), m_entity.left(2048));
    if (!m_text.isEmpty())
        s.insert(QStringLiteral("text"), m_text.left(KeelSchema::ContextTextMaxLength));
    return s;
}

// ---------------------------------------------------------------------------
// KeelShortcut
// ---------------------------------------------------------------------------

KeelShortcut::KeelShortcut(QObject *parent)
    : QObject(parent)
{
}

KeelShortcut::~KeelShortcut()
{
    if (m_registered)
        KeelActionRegistry::instance()->removeShortcut(this);
}

void KeelShortcut::componentComplete()
{
    KeelActionRegistry::instance()->addShortcut(this);
    m_registered = true;
}

QQmlListProperty<KeelParam> KeelShortcut::arguments()
{
    return listOf(this, &m_arguments);
}

QJsonObject KeelShortcut::prompt(const QString &appId) const
{
    QJsonArray arguments;
    for (const KeelParam *p : m_arguments) {
        QJsonObject a{{QStringLiteral("name"), p->name()}, {QStringLiteral("required"), p->isRequired()}};
        QJsonObject defs;
        const QJsonObject s = p->schema(appId, defs);
        if (s.contains(QLatin1String("description")))
            a.insert(QStringLiteral("description"), s.value(QLatin1String("description")));
        arguments.append(a);
    }
    QJsonArray steps;
    for (const QVariant &step : m_steps) {
        const QVariantMap map = step.toMap();
        QString action = map.value(QStringLiteral("action")).toString();
        if (!action.contains(QLatin1Char('/')))
            action = appId + QLatin1Char('/') + action;
        steps.append(QJsonObject{
            {QStringLiteral("tool"), action},
            {QStringLiteral("arguments"), KeelCall::toJson(map.value(QStringLiteral("arguments"), QVariantMap()))},
        });
    }
    QJsonObject prompt{
        {QStringLiteral("name"), appId + QLatin1Char('/') + m_name},
        {QStringLiteral("description"), m_description},
        {QStringLiteral("arguments"), arguments},
        {QStringLiteral("_meta"), QJsonObject{{KeelSchema::metaKey("steps"), steps}}},
    };
    if (!m_title.isEmpty())
        prompt.insert(QStringLiteral("title"), m_title);
    return prompt;
}
