#include <QTest>
#include <QSignalSpy>

#include "portalsettings.h"

class TestPortalSettings : public QObject {
    Q_OBJECT

    static QVariantMap ambience(const QString &scheme, const QString &highlight) {
        return {{QStringLiteral("/desktop/jolla/theme/color_scheme"), scheme},
                {QStringLiteral("/desktop/jolla/theme/color/highlight"), highlight}};
    }

  private slots:
    void darkAmbiencePrefersDark() {
        const auto a = PortalSettings::appearance(ambience("lightondark", "#759b97"));
        QCOMPARE(a.value("color-scheme").toUInt(), 1u);
    }
    void lightAmbiencePrefersLight() {
        const auto a = PortalSettings::appearance(ambience("darkonlight", "#759b97"));
        QCOMPARE(a.value("color-scheme").toUInt(), 2u);
    }
    void accentIsTheHighlight() {
        const auto   a = PortalSettings::appearance(ambience("lightondark", "#ff8000"));
        const QColor c = a.value("accent-color").value<QColor>();
        QCOMPARE(c, QColor(0xff8000));
    }
    void noAmbienceHasNoPreference() {
        const auto a = PortalSettings::appearance({});
        QCOMPARE(a.value("color-scheme").toUInt(), 0u);
        QVERIFY(!a.contains("accent-color"));
    }
    void readAllFiltersNamespaces() {
        const auto amb = ambience("lightondark", "#ff8000");
        QVERIFY(PortalSettings::matches(QStringLiteral("org.freedesktop.appearance"), {}));
        QVERIFY(PortalSettings::matches(QStringLiteral("org.freedesktop.appearance"),
                                        {QStringLiteral("org.freedesktop.*")}));
        QVERIFY(!PortalSettings::matches(QStringLiteral("org.freedesktop.appearance"),
                                         {QStringLiteral("org.gnome.*")}));
        Q_UNUSED(amb);
    }
    // xdg-desktop-portal wraps a backend's Read reply itself, so the backend
    // must answer with the bare value, as xdg-desktop-portal-gtk does.
    void readIsWrappedOnce() {
        PortalSettings s;
        s.setAmbience(ambience("lightondark", "#ff8000"));
        const QVariant v =
            s.Read(QStringLiteral("org.freedesktop.appearance"), QStringLiteral("color-scheme"))
                .variant();
        QCOMPARE(v.metaType(), QMetaType::fromType<uint>());
        QCOMPARE(v.toUInt(), 1u);
    }

    void gnomeInterfaceFollowsTheAmbience() {
        const auto dark = PortalSettings::settings(ambience("lightondark", "#7df0d4"), true)
                              .value("org.gnome.desktop.interface");
        QCOMPARE(dark.value("color-scheme").toString(), QString("prefer-dark"));
        QCOMPARE(dark.value("gtk-theme").toString(), QString("Marathon-dark"));
        QCOMPARE(dark.value("accent-color").toString(), QString("teal"));
        QCOMPARE(dark.value("font-name").toString(), QString("Source Sans 3 11"));
        QCOMPARE(dark.value("cursor-size").metaType(), QMetaType::fromType<int>());
        QCOMPARE(dark.value("enable-animations").toBool(), true);
        const auto light = PortalSettings::settings(ambience("darkonlight", "#7df0d4"), true)
                               .value("org.gnome.desktop.interface");
        QCOMPARE(light.value("color-scheme").toString(), QString("prefer-light"));
        QCOMPARE(light.value("gtk-theme").toString(), QString("Marathon"));
    }
    void gtk3FallsBackToAdwaitaWithoutTheTheme() {
        const auto gnome = PortalSettings::settings(ambience("lightondark", "#7df0d4"), false)
                               .value("org.gnome.desktop.interface");
        QCOMPARE(gnome.value("gtk-theme").toString(), QString("Adwaita-dark"));
    }
    // xdg-desktop-portal-kde's encoding: kdeglobals strings, colours "r,g,b".
    void kdeGlobalsAreServedAsStrings() {
        PortalSettings s;
        s.setAmbience(ambience("lightondark", "#7df0d4"));
        const PortalNamespaces all = s.ReadAll({QStringLiteral("org.kde.kdeglobals.*")});
        QVERIFY(all.contains("org.kde.kdeglobals.Colors:View"));
        QVERIFY(!all.contains("org.freedesktop.appearance"));
        QCOMPARE(all.value("org.kde.kdeglobals.Colors:Selection").value("BackgroundNormal"),
                 QVariant(QString("125,240,212")));
        QCOMPARE(all.value("org.kde.kdeglobals.General").value("ColorScheme"),
                 QVariant(QString("Marathon")));
        QCOMPARE(all.value("org.kde.kdeglobals.KDE").value("widgetStyle"),
                 QVariant(QString("Breeze")));
        QVERIFY(all.value("org.kde.kdeglobals.General")
                    .value("font")
                    .toString()
                    .startsWith("Source Sans 3,10,"));
    }
    void ambienceChangeAnnouncesKdeColoursOnce() {
        PortalSettings s;
        s.setAmbience(ambience("lightondark", "#7df0d4"));
        QSignalSpy spy(&s, &PortalSettings::SettingChanged);
        s.setAmbience(ambience("lightondark", "#ff8000"));
        int colorScheme = 0;
        for (const QList<QVariant> &args : std::as_const(spy)) {
            const QString ns = args.at(0).toString();
            QVERIFY2(!ns.startsWith("org.kde.kdeglobals.Colors:"), qPrintable(ns));
            if (ns == "org.kde.kdeglobals.General" && args.at(1).toString() == "ColorScheme")
                ++colorScheme;
        }
        QCOMPARE(colorScheme, 1);
        const auto accent = std::find_if(spy.cbegin(), spy.cend(), [](const QList<QVariant> &args) {
            return args.at(0) == "org.gnome.desktop.interface" && args.at(1) == "accent-color";
        });
        QVERIFY(accent != spy.cend());
        QCOMPARE(accent->at(2).value<QDBusVariant>().variant().toString(), QString("orange"));
    }
    void unchangedAmbienceIsSilent() {
        PortalSettings s;
        s.setAmbience(ambience("lightondark", "#7df0d4"));
        QSignalSpy spy(&s, &PortalSettings::SettingChanged);
        s.setAmbience(ambience("lightondark", "#7df0d4"));
        QCOMPARE(spy.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestPortalSettings)
#include "test_portalsettings.moc"
