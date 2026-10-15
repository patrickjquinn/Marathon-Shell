#include "services/automatictimezone.h"

#include <QFile>
#include <QTemporaryFile>
#include <QTest>

class TestAutomaticTimeZone : public QObject {
    Q_OBJECT

  private slots:
    void nearestSystemZone_data() {
        QTest::addColumn<double>("lat");
        QTest::addColumn<double>("lon");
        QTest::addColumn<QString>("zone");
        QTest::newRow("Dublin") << 53.35 << -6.26 << "Europe/Dublin";
        QTest::newRow("Cork") << 51.90 << -8.47 << "Europe/Dublin";
        QTest::newRow("Galway") << 53.27 << -9.05 << "Europe/Dublin";
        QTest::newRow("London") << 51.51 << -0.13 << "Europe/London";
        QTest::newRow("Berlin") << 52.52 << 13.40 << "Europe/Berlin";
        QTest::newRow("Brooklyn") << 40.68 << -73.94 << "America/New_York";
        QTest::newRow("Sydney") << -33.87 << 151.21 << "Australia/Sydney";
        QTest::newRow("Tokyo") << 35.68 << 139.69 << "Asia/Tokyo";
    }
    void nearestSystemZone() {
        if (!QFile::exists(QStringLiteral("/usr/share/zoneinfo/zone.tab")))
            QSKIP("no system zone.tab");
        QFETCH(double, lat);
        QFETCH(double, lon);
        QFETCH(QString, zone);
        QCOMPARE(AutomaticTimeZone::nearestZone(lat, lon), zone);
    }

    void parsesSecondsAndWrapsTheDateLine() {
        QTemporaryFile tab;
        QVERIFY(tab.open());
        tab.write("# comment\n"
                  "US\t+404251-0740023\tAmerica/New_York\tEastern\n"
                  "FJ\t-1808+17825\tPacific/Fiji\n"
                  "WS\t-1350-17144\tPacific/Apia\n");
        tab.close();
        QCOMPARE(AutomaticTimeZone::nearestZone(40.7, -74.0, tab.fileName()), "America/New_York");
        // 179.9 W is nearer Fiji (178.4 E) than Apia (171.7 W).
        QCOMPARE(AutomaticTimeZone::nearestZone(-18.0, -179.9, tab.fileName()), "Pacific/Fiji");
    }

    void missingTableGivesNoZone() {
        QCOMPARE(AutomaticTimeZone::nearestZone(0, 0, QStringLiteral("/nonexistent/zone.tab")),
                 QString());
    }
};

QTEST_GUILESS_MAIN(TestAutomaticTimeZone)
#include "test_automatictimezone.moc"
