#include "portalsettings.h"
#include "../services/toolkittheme.h"

#include <QDBusMessage>
#include <QDBusMetaType>

#include <utility>

namespace {
    using namespace Qt::StringLiterals;
    constexpr auto kAppearance  = "org.freedesktop.appearance"_L1;
    constexpr auto kGnome       = "org.gnome.desktop.interface"_L1;
    constexpr auto kKde         = "org.kde.kdeglobals."_L1;
    constexpr auto kKdeGeneral  = "org.kde.kdeglobals.General"_L1;
    constexpr auto kColorScheme = "ColorScheme"_L1;
    // Marathon's UI faces: Source Sans 3 stands in for Sail Sans Pro.
    constexpr auto kSans = "Source Sans 3"_L1;
    constexpr auto kMono = "JetBrains Mono"_L1;

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

    // QFont::toString's form, which kdeglobals stores and KFontSettingsData parses.
    QString kdeFont(QLatin1StringView family, int points) {
        return QStringLiteral("%1,%2,-1,5,400,0,0,0,0,0,0,0,0,0,0,1")
            .arg(family, QString::number(points));
    }

    bool isKdeColors(const QString &ns) {
        return ns.startsWith("org.kde.kdeglobals.Colors:"_L1) || ns == "org.kde.kdeglobals.WM"_L1;
    }
} // namespace

Q_DECLARE_METATYPE(Rgb)

namespace {
    QVariant dbusValue(const QVariant &v) {
        if (v.metaType() == QMetaType::fromType<QColor>()) {
            const QColor c = v.value<QColor>();
            return QVariant::fromValue(Rgb{c.redF(), c.greenF(), c.blueF()});
        }
        return v;
    }
} // namespace

PortalSettings::PortalSettings(QObject *parent)
    : QObject(parent) {
    qDBusRegisterMetaType<Rgb>();
    qDBusRegisterMetaType<PortalNamespaces>();
    m_settings = settings({}, false);
}

QVariantMap PortalSettings::appearance(const QVariantMap &ambience) {
    const QString scheme =
        ambience.value(QStringLiteral("/desktop/jolla/theme/color_scheme")).toString();
    const QColor accent(
        ambience.value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString());
    QVariantMap out;
    out.insert(QStringLiteral("color-scheme"),
               scheme == QLatin1String("lightondark")     ? 1u :
                   scheme == QLatin1String("darkonlight") ? 2u :
                                                            0u);
    if (accent.isValid())
        out.insert(QStringLiteral("accent-color"), accent);
    return out;
}

PortalNamespaces PortalSettings::settings(const QVariantMap &ambience, bool gtk3Theme) {
    const QVariantMap fdo    = appearance(ambience);
    const uint        scheme = fdo.value(QStringLiteral("color-scheme")).toUInt();
    const QString     theme  = gtk3Theme ? QStringLiteral("Marathon") : QStringLiteral("Adwaita");

    QVariantMap       gnome = {
        {QStringLiteral("color-scheme"),
         scheme == 1     ? QStringLiteral("prefer-dark") :
             scheme == 2 ? QStringLiteral("prefer-light") :
                           QStringLiteral("default")},
        {QStringLiteral("gtk-theme"), scheme == 1 ? theme + QStringLiteral("-dark") : theme},
        {QStringLiteral("icon-theme"), QStringLiteral("Adwaita")},
        {QStringLiteral("font-name"), QString(kSans) + QStringLiteral(" 11")},
        {QStringLiteral("monospace-font-name"), QString(kMono) + QStringLiteral(" 10")},
        {QStringLiteral("cursor-size"), 24},
        {QStringLiteral("enable-animations"), true},
    };

    KdeGroups kde = {
        {QStringLiteral("General"),
         {{QStringLiteral("font"), kdeFont(kSans, 10)},
          {QStringLiteral("menuFont"), kdeFont(kSans, 10)},
          {QStringLiteral("toolBarFont"), kdeFont(kSans, 10)},
          {QStringLiteral("smallestReadableFont"), kdeFont(kSans, 8)},
          {QStringLiteral("fixed"), kdeFont(kMono, 10)}}},
        {QStringLiteral("KDE"), {{QStringLiteral("widgetStyle"), QStringLiteral("Breeze")}}},
        {QStringLiteral("Icons"), {{QStringLiteral("Theme"), QStringLiteral("breeze")}}},
    };

    if (fdo.contains(QStringLiteral("accent-color"))) {
        const QColor accent = fdo.value(QStringLiteral("accent-color")).value<QColor>();
        gnome.insert(QStringLiteral("accent-color"), ToolkitTheme::gnomeAccent(accent));
        kde.insert(ToolkitTheme::kdeColors(ToolkitTheme::palette(accent, scheme != 2)));
        kde[QStringLiteral("General")].insert(kColorScheme, QStringLiteral("Marathon"));
        kde[QStringLiteral("WM")].insert(QStringLiteral("activeFont"), kdeFont(kSans, 10));
    }

    PortalNamespaces out = {{kAppearance, fdo}, {kGnome, gnome}};
    for (auto group = kde.cbegin(); group != kde.cend(); ++group) {
        QVariantMap values;
        for (auto it = group->cbegin(); it != group->cend(); ++it)
            values.insert(it.key(), it.value());
        out.insert(kKde + group.key(), values);
    }
    return out;
}

bool PortalSettings::matches(const QString &ns, const QStringList &filters) {
    if (filters.isEmpty())
        return true;
    for (const QString &f : filters) {
        if (f.isEmpty() || f == ns ||
            (f.endsWith(QLatin1String(".*")) && ns.startsWith(f.chopped(1))))
            return true;
    }
    return false;
}

void PortalSettings::setGtk3Theme(bool installed) {
    m_gtk3Theme = installed;
}

// KDE's platform theme reloads the whole palette when General/ColorScheme
// changes and ignores the colour keys themselves, as xdg-desktop-portal-kde
// signals it, so the colours are announced through that key alone.
void PortalSettings::setAmbience(const QVariantMap &ambience) {
    const PortalNamespaces prev       = std::exchange(m_settings, settings(ambience, m_gtk3Theme));
    bool                   kdeChanged = false;
    for (auto ns = m_settings.cbegin(); ns != m_settings.cend(); ++ns) {
        const QVariantMap old = prev.value(ns.key());
        for (auto it = ns->cbegin(); it != ns->cend(); ++it) {
            if (old.value(it.key()) == it.value())
                continue;
            if (isKdeColors(ns.key()) || (ns.key() == kKdeGeneral && it.key() == kColorScheme))
                kdeChanged = true;
            else
                emit SettingChanged(ns.key(), it.key(), QDBusVariant(dbusValue(it.value())));
        }
    }
    const QVariant scheme = m_settings.value(kKdeGeneral).value(kColorScheme);
    if (kdeChanged && scheme.isValid())
        emit SettingChanged(kKdeGeneral, kColorScheme, QDBusVariant(scheme));
}

PortalNamespaces PortalSettings::ReadAll(const QStringList &namespaces) {
    PortalNamespaces out;
    for (auto ns = m_settings.cbegin(); ns != m_settings.cend(); ++ns) {
        if (!matches(ns.key(), namespaces))
            continue;
        QVariantMap values;
        for (auto it = ns->cbegin(); it != ns->cend(); ++it)
            values.insert(it.key(), dbusValue(it.value()));
        out.insert(ns.key(), values);
    }
    return out;
}

QDBusVariant PortalSettings::ReadOne(const QString &ns, const QString &key) {
    const QVariantMap values = m_settings.value(ns);
    if (values.contains(key))
        return QDBusVariant(dbusValue(values.value(key)));
    if (calledFromDBus())
        sendErrorReply(QStringLiteral("org.freedesktop.portal.Error.NotFound"),
                       QStringLiteral("Requested setting not found"));
    return {};
}

QDBusVariant PortalSettings::Read(const QString &ns, const QString &key) {
    return ReadOne(ns, key);
}
