// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keelschema.h"

#include <QJsonArray>
#include <QRegularExpression>
#include <QStringList>

#include <cmath>

namespace KeelSchema {

QString qualifiedEntity(const QString &entity, const QString &appId)
{
    return entity.contains(QLatin1Char('/')) ? entity : appId + QLatin1Char('/') + entity;
}

QString escapeRegex(const QString &text)
{
    static const QString meta = QStringLiteral("\\.+*?()|[]{}^$-");
    QString out;
    for (const QChar c : text) {
        if (meta.contains(c))
            out += QLatin1Char('\\');
        out += c;
    }
    return out;
}

QString entityDefName(const QString &qualified)
{
    QString name = qualified;
    name.replace(QLatin1Char('/'), QLatin1Char('.'));
    return name;
}

QJsonObject entityRefDef(const QString &qualified)
{
    const qsizetype slash = qualified.lastIndexOf(QLatin1Char('/'));
    const QString app = qualified.left(slash);
    const QString type = qualified.mid(slash + 1);
    const QString prefix = QStringLiteral("keel://") + app + QLatin1Char('/') + type + QLatin1Char('/');
    return QJsonObject{
        {QStringLiteral("type"), QStringLiteral("string")},
        {QStringLiteral("format"), QStringLiteral("uri")},
        {QStringLiteral("pattern"), QLatin1Char('^') + escapeRegex(prefix)
                                        + QStringLiteral("[^/?#\\s]{1,%1}$").arg(IdMaxLength)},
        {QStringLiteral("maxLength"), static_cast<int>(prefix.size()) + IdMaxLength},
        {QStringLiteral("x-keel-entity"), qualified},
    };
}

QJsonObject entityRef(const QString &qualified, QJsonObject &defs)
{
    const QString name = entityDefName(qualified);
    if (!defs.contains(name))
        defs.insert(name, entityRefDef(qualified));
    return QJsonObject{{QStringLiteral("$ref"), QStringLiteral("#/$defs/") + name}};
}

QJsonObject object(const QJsonObject &properties, const QStringList &required)
{
    QJsonObject schema{
        {QStringLiteral("type"), QStringLiteral("object")},
        {QStringLiteral("properties"), properties},
        {QStringLiteral("additionalProperties"), false},
    };
    if (!required.isEmpty())
        schema.insert(QStringLiteral("required"), QJsonArray::fromStringList(required));
    return schema;
}

QJsonObject wrapResult(const QJsonObject &schema)
{
    return object(QJsonObject{{QStringLiteral("result"), schema}}, {QStringLiteral("result")});
}

namespace {

QString typeOf(const QJsonValue &value)
{
    switch (value.type()) {
    case QJsonValue::Null:
        return QStringLiteral("null");
    case QJsonValue::Bool:
        return QStringLiteral("boolean");
    case QJsonValue::Double: {
        const double d = value.toDouble();
        return std::isfinite(d) && std::floor(d) == d ? QStringLiteral("integer") : QStringLiteral("number");
    }
    case QJsonValue::String:
        return QStringLiteral("string");
    case QJsonValue::Array:
        return QStringLiteral("array");
    case QJsonValue::Object:
        return QStringLiteral("object");
    case QJsonValue::Undefined:
        break;
    }
    return QStringLiteral("undefined");
}

bool typeMatches(const QString &wanted, const QString &actual)
{
    return wanted == actual || (wanted == QLatin1String("number") && actual == QLatin1String("integer"));
}

QString escapePointer(QString token)
{
    token.replace(QLatin1Char('~'), QLatin1String("~0"));
    token.replace(QLatin1Char('/'), QLatin1String("~1"));
    return token;
}

QString check(const QJsonObject &schema, const QJsonValue &value, const QJsonObject &root,
              const QString &path, int depth)
{
    const QString at = path.isEmpty() ? QStringLiteral("/") : path;
    if (depth > 32)
        return at + QStringLiteral(": schema nests too deeply");

    if (schema.contains(QLatin1String("$ref"))) {
        const QString ref = schema.value(QLatin1String("$ref")).toString();
        const QString prefix = QStringLiteral("#/$defs/");
        if (!ref.startsWith(prefix))
            return at + QStringLiteral(": unsupported $ref ") + ref;
        const QJsonValue target = root.value(QLatin1String("$defs")).toObject().value(ref.mid(prefix.size()));
        if (!target.isObject())
            return at + QStringLiteral(": unresolved $ref ") + ref;
        return check(target.toObject(), value, root, path, depth + 1);
    }

    const QString actual = typeOf(value);
    if (schema.contains(QLatin1String("type"))) {
        const QJsonValue type = schema.value(QLatin1String("type"));
        bool ok = false;
        QStringList wanted;
        if (type.isArray()) {
            for (const auto &t : type.toArray())
                wanted << t.toString();
        } else {
            wanted << type.toString();
        }
        for (const QString &w : wanted)
            ok = ok || typeMatches(w, actual);
        if (!ok)
            return at + QStringLiteral(": expected ") + wanted.join(QLatin1String(" or ")) + QStringLiteral(", got ")
                + actual;
    }

    if (schema.contains(QLatin1String("enum"))) {
        bool found = false;
        for (const auto &v : schema.value(QLatin1String("enum")).toArray())
            found = found || v == value;
        if (!found)
            return at + QStringLiteral(": not one of the allowed values");
    }

    if (value.isString()) {
        const qsizetype length = value.toString().toUcs4().size();
        if (schema.contains(QLatin1String("maxLength")) && length > schema.value(QLatin1String("maxLength")).toInteger())
            return at + QStringLiteral(": longer than %1 characters").arg(schema.value(QLatin1String("maxLength")).toInteger());
        if (schema.contains(QLatin1String("minLength")) && length < schema.value(QLatin1String("minLength")).toInteger())
            return at + QStringLiteral(": shorter than %1 characters").arg(schema.value(QLatin1String("minLength")).toInteger());
        if (schema.contains(QLatin1String("pattern"))) {
            const QRegularExpression re(schema.value(QLatin1String("pattern")).toString());
            if (!re.isValid())
                return at + QStringLiteral(": invalid pattern in schema");
            if (!re.match(value.toString()).hasMatch())
                return at + QStringLiteral(": does not match the pattern ") + re.pattern();
        }
    }

    if (value.isDouble()) {
        const double d = value.toDouble();
        if (schema.contains(QLatin1String("minimum")) && d < schema.value(QLatin1String("minimum")).toDouble())
            return at + QStringLiteral(": below the minimum ") + QString::number(schema.value(QLatin1String("minimum")).toDouble());
        if (schema.contains(QLatin1String("maximum")) && d > schema.value(QLatin1String("maximum")).toDouble())
            return at + QStringLiteral(": above the maximum ") + QString::number(schema.value(QLatin1String("maximum")).toDouble());
    }

    if (value.isArray()) {
        const QJsonArray array = value.toArray();
        if (schema.contains(QLatin1String("maxItems")) && array.size() > schema.value(QLatin1String("maxItems")).toInteger())
            return at + QStringLiteral(": more than %1 items").arg(schema.value(QLatin1String("maxItems")).toInteger());
        if (schema.contains(QLatin1String("minItems")) && array.size() < schema.value(QLatin1String("minItems")).toInteger())
            return at + QStringLiteral(": fewer than %1 items").arg(schema.value(QLatin1String("minItems")).toInteger());
        if (schema.value(QLatin1String("items")).isObject()) {
            const QJsonObject items = schema.value(QLatin1String("items")).toObject();
            for (qsizetype i = 0; i < array.size(); ++i) {
                const QString error = check(items, array.at(i), root, path + QLatin1Char('/') + QString::number(i), depth + 1);
                if (!error.isEmpty())
                    return error;
            }
        }
    }

    if (value.isObject()) {
        const QJsonObject object = value.toObject();
        const QJsonObject properties = schema.value(QLatin1String("properties")).toObject();
        for (const auto &name : schema.value(QLatin1String("required")).toArray()) {
            if (!object.contains(name.toString()))
                return at + QStringLiteral(": missing required property \"") + name.toString() + QLatin1Char('"');
        }
        const bool closed = schema.value(QLatin1String("additionalProperties")) == QJsonValue(false);
        for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
            const QString child = path + QLatin1Char('/') + escapePointer(it.key());
            if (properties.contains(it.key())) {
                const QString error = check(properties.value(it.key()).toObject(), it.value(), root, child, depth + 1);
                if (!error.isEmpty())
                    return error;
            } else if (closed) {
                return child + QStringLiteral(": unknown property");
            }
        }
    }
    return {};
}

} // namespace

QString validate(const QJsonObject &schema, const QJsonValue &value, const QJsonObject &root)
{
    return check(schema, value, root, QString(), 0);
}

} // namespace KeelSchema
