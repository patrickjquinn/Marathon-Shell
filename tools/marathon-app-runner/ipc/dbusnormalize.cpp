#include "dbusnormalize.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusVariant>

QVariantList normalizeListDeep(const QVariantList &in) {
    QVariantList out;
    out.reserve(in.size());
    for (const QVariant &it : in)
        out.push_back(normalizeDbusVariantDeep(it));
    return out;
}

QVariantMap normalizeMapDeep(const QVariantMap &in) {
    QVariantMap out;
    for (auto it = in.constBegin(); it != in.constEnd(); ++it)
        out.insert(it.key(), normalizeDbusVariantDeep(it.value()));
    return out;
}

// Decodes by the argument's own signature, once: canConvert<QDBusVariant>()
// is true for any QDBusArgument, and reading a map or array as a variant
// crashes libdbus.
static QVariant fromDbusArgument(const QDBusArgument &arg) {
    const QString sig = arg.currentSignature();
    if (sig == QLatin1String("a{sv}"))
        return normalizeMapDeep(qdbus_cast<QVariantMap>(arg));
    if (sig == QLatin1String("av"))
        return normalizeListDeep(qdbus_cast<QVariantList>(arg));
    if (sig == QLatin1String("as"))
        return qdbus_cast<QStringList>(arg);
    if (sig == QLatin1String("v"))
        return normalizeDbusVariantDeep(qdbus_cast<QDBusVariant>(arg).variant());
    return QVariant::fromValue(arg);
}

QVariant normalizeDbusVariantDeep(QVariant v) {
    if (v.userType() == qMetaTypeId<QDBusVariant>())
        v = v.value<QDBusVariant>().variant();

    if (v.userType() == qMetaTypeId<QDBusArgument>())
        return fromDbusArgument(v.value<QDBusArgument>());

    if (v.metaType().id() == QMetaType::QVariantList)
        return normalizeListDeep(v.toList());
    if (v.metaType().id() == QMetaType::QVariantMap)
        return normalizeMapDeep(v.toMap());

    return v;
}

QVariantList unwrapDbusVariantList(const QVariant &v) {
    return normalizeDbusVariantDeep(v).toList();
}
