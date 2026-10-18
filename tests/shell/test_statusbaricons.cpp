#include <QFile>
#include <QTest>

#include "statusbariconservicecpp.h"

class TestStatusBarIcons : public QObject {
    Q_OBJECT

    StatusBarIconServiceCpp m_icons;
    QByteArray              m_glyphs;

    bool exists(const QString &name) const {
        return m_glyphs.contains("\"" + name.toUtf8() + "\":");
    }

  private slots:
    void initTestCase() {
        QFile f(QStringLiteral(GLYPHS_JS));
        QVERIFY(f.open(QIODevice::ReadOnly));
        m_glyphs = f.readAll();
    }

    void wifiGlyphsExistAndDiffer() {
        const QString disconnected = m_icons.getWifiIcon(true, 0, false);
        QCOMPARE(disconnected, QStringLiteral("wifi-slash"));
        for (int strength : {0, 30, 60, 100}) {
            const QString name = m_icons.getWifiIcon(true, strength, true);
            QVERIFY2(exists(name), qPrintable(name));
            QVERIFY(name != disconnected);
        }
        QVERIFY(exists(disconnected));
        QCOMPARE(m_icons.getWifiIcon(true, 0, true), m_icons.getWifiIcon(true, 30, true));
        QVERIFY(m_icons.getWifiIcon(true, 30, true) != m_icons.getWifiIcon(true, 100, true));
    }

    void bluetoothConnectedHasItsOwnGlyph() {
        const QString on        = m_icons.getBluetoothIcon(true, false);
        const QString connected = m_icons.getBluetoothIcon(true, true);
        QVERIFY(exists(on));
        QVERIFY(exists(connected));
        QVERIFY(on != connected);
    }

    void signalStrengthIsTheGlyph() {
        QStringList names;
        for (int strength : {0, 20, 45, 70, 100}) {
            const QString name = m_icons.getSignalIcon(strength);
            QVERIFY2(exists(name), qPrintable(name));
            names << name;
        }
        names.removeDuplicates();
        QCOMPARE(names.size(), 5);
    }

    void batteryGlyphsExist() {
        for (int level : {5, 20, 40, 90})
            QVERIFY(exists(m_icons.getBatteryIcon(level, false)));
        QVERIFY(exists(m_icons.getBatteryIcon(50, true)));
    }
};

QTEST_GUILESS_MAIN(TestStatusBarIcons)
#include "test_statusbaricons.moc"
