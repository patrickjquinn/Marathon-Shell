#include <QTest>
#include <QSignalSpy>
#include <QCoreApplication>
#include <QTemporaryDir>

#include "marathon-shell-native/src/display.cxxqt.h"

// Brightness on a 10-level PWM backlight (the HackberryPi's) with a 10%
// visible floor, and auto-brightness only where there is a light sensor.
class TestBrightness : public QObject {
    Q_OBJECT

    QTemporaryDir m_sysfs;

    QString       file(const QString &name) const {
        return m_sysfs.filePath(QStringLiteral("backlight/panel/") + name);
    }

    void write(const QString &path, const QByteArray &value) {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
        f.write(value);
    }

    int level() {
        QFile f(file(QStringLiteral("brightness")));
        return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed().toInt() : -1;
    }

    void setLevel(int l) {
        write(file(QStringLiteral("brightness")), QByteArray::number(l) + '\n');
        write(file(QStringLiteral("actual_brightness")), QByteArray::number(l) + '\n');
    }

    // The user value a hardware level shows as, through the 10% floor.
    static double shownAs(int l) {
        return (l / 10.0 - 0.1) / 0.9;
    }

    // A display on the fake sysfs, with sensors from `iio` and a 10% floor.
    void start(marathon::Display &display, const QString &iio = QStringLiteral("iio-none")) {
        display.start(m_sysfs.filePath(QStringLiteral("backlight")), m_sysfs.filePath(iio), 0.1);
    }

  private slots:
    void initTestCase() {
        QVERIFY(QDir(m_sysfs.path()).mkpath(QStringLiteral("backlight/panel")));
        QVERIFY(QDir(m_sysfs.path()).mkpath(QStringLiteral("iio-none")));
        QVERIFY(QDir(m_sysfs.path()).mkpath(QStringLiteral("iio-light/iio:device0")));
        write(m_sysfs.filePath(QStringLiteral("iio-light/iio:device0/in_illuminance_raw")), "40\n");
        write(file(QStringLiteral("max_brightness")), "10\n");
        write(file(QStringLiteral("bl_power")), "0\n");
    }

    void increaseLandsOnTheNextLevel() {
        setLevel(8);
        marathon::Display display;
        start(display);
        QCOMPARE(qRound(display.getBrightness() * 100), 78);
        // The test app's Increase: +10%.
        display.setBrightness(display.getBrightness() + 0.1);
        QTRY_COMPARE(level(), 9);
        QCOMPARE(display.getBrightness(), shownAs(9));
    }

    void decreaseLandsOnTheLevelBelow() {
        setLevel(8);
        marathon::Display display;
        start(display);
        display.setBrightness(display.getBrightness() - 0.1);
        QTRY_COMPARE(level(), 7);
    }

    void everyStepMovesOneLevel() {
        setLevel(1);
        marathon::Display display;
        start(display);
        for (int l = 2; l <= 10; ++l) {
            display.setBrightness(display.getBrightness() + 0.1);
            QTRY_COMPARE(level(), l);
        }
        for (int l = 9; l >= 1; --l) {
            display.setBrightness(display.getBrightness() - 0.1);
            QTRY_COMPARE(level(), l);
        }
    }

    void aWakeRestoresTheSameLevel() {
        setLevel(8);
        marathon::Display display;
        start(display);
        display.setBrightness(display.getBrightness() + 0.1);
        display.turnScreenOff(QStringLiteral("test"));
        display.turnScreenOn();
        QTRY_COMPARE(level(), 9);
    }

    void aValueRoundsToTheNearestLevel() {
        setLevel(3);
        marathon::Display display;
        start(display);
        display.setBrightness(0.75); // 7.75 of 10
        QTRY_COMPARE(level(), 8);
        display.setBrightness(1.0);
        QTRY_COMPARE(level(), 10);
        display.setBrightness(0.0);
        QTRY_COMPARE(level(), 1);
    }

    void theEffectiveValueIsReported() {
        setLevel(8);
        marathon::Display display;
        start(display);
        QSignalSpy changed(&display, &marathon::Display::brightnessChanged);
        display.setBrightness(0.95);
        QCOMPARE(changed.count(), 1);
        QCOMPARE(display.getBrightness(), 1.0);
    }

    void noLightSensorMeansNoAutoBrightness() {
        marathon::Display display;
        start(display);
        QVERIFY(!display.getLightAvailable());
        display.setAutoBrightness(true);
        QVERIFY(!display.getAutoBrightness());
    }

    void theLightSensorIsReadOnlyWhileWanted() {
        marathon::Display display;
        start(display, QStringLiteral("iio-light"));
        display.setAutoBrightness(true);
        QTRY_COMPARE(display.getAmbientLight(), 40);
        display.setAutoBrightness(false);
        write(m_sysfs.filePath(QStringLiteral("iio-light/iio:device0/in_illuminance_raw")), "900\n");
        QTest::qWait(1500);
        QCOMPARE(display.getAmbientLight(), 40);
        display.setAutoBrightness(true);
        QTRY_COMPARE(display.getAmbientLight(), 900);
        write(m_sysfs.filePath(QStringLiteral("iio-light/iio:device0/in_illuminance_raw")), "40\n");
    }

    void theLightSensorRestsWhileTheScreenIsOff() {
        marathon::Display display;
        start(display, QStringLiteral("iio-light"));
        display.setAutoBrightness(true);
        QTRY_COMPARE(display.getAmbientLight(), 40);
        display.turnScreenOff(QStringLiteral("test"));
        write(m_sysfs.filePath(QStringLiteral("iio-light/iio:device0/in_illuminance_raw")), "900\n");
        QTest::qWait(1500);
        QCOMPARE(display.getAmbientLight(), 40);
        write(m_sysfs.filePath(QStringLiteral("iio-light/iio:device0/in_illuminance_raw")), "40\n");
    }
};

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    TestBrightness   test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_brightness.moc"
