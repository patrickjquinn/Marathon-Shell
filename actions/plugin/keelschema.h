// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's JSON Schema subset (ADR-0018, decision 4), the C++ side. The Rust
// side is keel/actions/schema (keel-actions-schema); both produce the same
// schemas for the same declarations (checked by keel_actions_describe_golden)
// and accept the same values.
//
// Keywords: type, properties, required, additionalProperties (false only),
// items, minItems, maxItems, minLength, maxLength, pattern, enum, minimum,
// maximum, $ref (local "#/$defs/<name>"), $defs. Annotations that do not
// constrain (title, description, default, format, x-keel-*) are ignored.
#ifndef KEEL_ACTIONS_SCHEMA_H
#define KEEL_ACTIONS_SCHEMA_H

#include <QJsonObject>
#include <QJsonValue>
#include <QString>

namespace KeelSchema {

// Default and maximum bounds.
constexpr int DefaultMaxLength = 4096;
constexpr int DefaultMaxItems = 100;
constexpr qint64 DefaultIntMin = -2147483648LL;
constexpr qint64 DefaultIntMax = 2147483647LL;
constexpr int IdMaxLength = 256;
constexpr int TitleMaxLength = 512;
constexpr int ContextTextMaxLength = 4000;
constexpr int ContextPurposeMaxLength = 200;
constexpr int FindQueryMaxLength = 256;
constexpr int FindLimitMax = 50;

// The MCP / _meta namespace.
inline QString metaKey(const char *name)
{
    return QStringLiteral("org.shipwright.keel/") + QLatin1String(name);
}

// "<type>" of `appId`, or "<app-id>/<type>" -> "<app-id>/<type>".
QString qualifiedEntity(const QString &entity, const QString &appId);
// Backslash before regex metacharacters (\.+*?()|[]{}^$-), as the Rust
// generator does, so both write identical patterns.
QString escapeRegex(const QString &text);
// The $defs name and definition of an entity reference.
QString entityDefName(const QString &qualified);
QJsonObject entityRefDef(const QString &qualified);
// A $ref to it, adding the definition to `defs`.
QJsonObject entityRef(const QString &qualified, QJsonObject &defs);

// An object schema from properties (name -> schema) and required names.
QJsonObject object(const QJsonObject &properties, const QStringList &required);

// MCP output schemas are objects: other result types are wrapped as
// { "result": <value> }.
QJsonObject wrapResult(const QJsonObject &schema);

// Validates `value` against `schema`; `root` holds $defs. Returns an empty
// string, or "<json pointer>: <reason>".
QString validate(const QJsonObject &schema, const QJsonValue &value, const QJsonObject &root);
inline QString validate(const QJsonObject &schema, const QJsonValue &value)
{
    return validate(schema, value, schema);
}

} // namespace KeelSchema

#endif
