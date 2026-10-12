#include "portalsettings.h"

#include <QDBusMessage>
#include <QDBusMetaType>

namespace {
using namespace Qt::StringLiterals;
constexpr auto kAppearance = "org.freedesktop.appearance"_L1;

struct Rgb {
    double r = 0, g = 0, b = 0;
};

QDBusArgument &operator<<(QDBusArgument &arg, const Rgb &c) {
    arg.beginStructure();
    arg << c.r << c.g << c.b;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, Rgb &c) {
    arg.beginStructure();
    arg >> c.r >> c.g >> c.b;
    arg.endStructure();
    return arg;
}
} // namespace

Q_DECLARE_METATYPE(Rgb)

PortalSettings::PortalSettings(QObject *parent)
    : QObject(parent) {
    qDBusRegisterMetaType<Rgb>();
    qDBusRegisterMetaType<PortalNamespaces>();
    m_appearance = appearance({});
}

QVariantMap PortalSettings::appearance(const QVariantMap &ambience) {
    const QString scheme = ambience.value(QStringLiteral("/desktop/jolla/theme/color_scheme")).toString();
    const QColor  accent(ambience.value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString());
    QVariantMap   out;
    out.insert(QStringLiteral("color-scheme"),
               scheme == QLatin1String("lightondark")   ? 1u
               : scheme == QLatin1String("darkonlight") ? 2u
                                                       : 0u);
    if (accent.isValid())
        out.insert(QStringLiteral("accent-color"), accent);
    return out;
}

bool PortalSettings::matches(const QString &ns, const QStringList &filters) {
    if (filters.isEmpty())
        return true;
    for (const QString &f : filters) {
        if (f.isEmpty() || f == ns || (f.endsWith(QLatin1String(".*")) && ns.startsWith(f.chopped(1))))
            return true;
    }
    return false;
}

void PortalSettings::setAmbience(const QVariantMap &ambience) {
    const QVariantMap next = appearance(ambience);
    const QVariantMap prev = m_appearance;
    m_appearance           = next;
    for (const QString &key : {QStringLiteral("color-scheme"), QStringLiteral("accent-color")}) {
        if (prev.value(key) != next.value(key) && next.contains(key))
            emit SettingChanged(kAppearance, key, QDBusVariant(dbusValue(key)));
    }
}

QVariant PortalSettings::dbusValue(const QString &key) const {
    if (key == QLatin1String("accent-color")) {
        const QColor c = m_appearance.value(key).value<QColor>();
        return QVariant::fromValue(Rgb{c.redF(), c.greenF(), c.blueF()});
    }
    return m_appearance.value(key);
}

PortalNamespaces PortalSettings::ReadAll(const QStringList &namespaces) {
    PortalNamespaces out;
    if (!matches(kAppearance, namespaces))
        return out;
    QVariantMap values;
    for (auto it = m_appearance.cbegin(); it != m_appearance.cend(); ++it)
        values.insert(it.key(), dbusValue(it.key()));
    out.insert(kAppearance, values);
    return out;
}

QDBusVariant PortalSettings::ReadOne(const QString &ns, const QString &key) {
    if (ns == kAppearance && m_appearance.contains(key))
        return QDBusVariant(dbusValue(key));
    if (calledFromDBus())
        sendErrorReply(QStringLiteral("org.freedesktop.portal.Error.NotFound"),
                       QStringLiteral("Requested setting not found"));
    return {};
}

QDBusVariant PortalSettings::Read(const QString &ns, const QString &key) {
    // The deprecated Read wraps the value in a second variant.
    return QDBusVariant(QVariant::fromValue(ReadOne(ns, key)));
}
