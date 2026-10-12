#include <QtTest>

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
        const auto a = PortalSettings::appearance(ambience("lightondark", "#ff8000"));
        const QColor c = a.value("accent-color").value<QColor>();
        QCOMPARE(c, QColor("#ff8000"));
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
};

QTEST_GUILESS_MAIN(TestPortalSettings)
#include "test_portalsettings.moc"
