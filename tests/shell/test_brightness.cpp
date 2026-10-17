#include <QtTest>
#include <QCoreApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "managers/displaymanagercpp.h"

// Brightness on a 10-level PWM backlight (the HackberryPi's) with a 10%
// visible floor.
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

    QString backlightDir() const {
        return m_sysfs.filePath(QStringLiteral("backlight"));
    }

  private slots:
    void initTestCase() {
        QVERIFY(QDir(m_sysfs.path()).mkpath(QStringLiteral("backlight/panel")));
        write(file(QStringLiteral("max_brightness")), "10\n");
        write(file(QStringLiteral("bl_power")), "0\n");
    }

    void increaseLandsOnTheNextLevel() {
        setLevel(8);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        QCOMPARE(qRound(display.brightness() * 100), 78);
        // The test app's Increase: +10%.
        display.setBrightness(display.brightness() + 0.1);
        QCOMPARE(level(), 9);
        QCOMPARE(display.brightness(), shownAs(9));
    }

    void decreaseLandsOnTheLevelBelow() {
        setLevel(8);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        display.setBrightness(display.brightness() - 0.1);
        QCOMPARE(level(), 7);
    }

    void everyStepMovesOneLevel() {
        setLevel(1);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        for (int l = 2; l <= 10; ++l) {
            display.setBrightness(display.brightness() + 0.1);
            QCOMPARE(level(), l);
        }
        for (int l = 9; l >= 1; --l) {
            display.setBrightness(display.brightness() - 0.1);
            QCOMPARE(level(), l);
        }
    }

    void aWakeRestoresTheSameLevel() {
        setLevel(8);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        display.setBrightness(display.brightness() + 0.1);
        display.setScreenState(false);
        display.setScreenState(true);
        QCOMPARE(level(), 9);
    }

    void aValueRoundsToTheNearestLevel() {
        setLevel(3);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        display.setBrightness(0.75); // 7.75 of 10
        QCOMPARE(level(), 8);
        display.setBrightness(1.0);
        QCOMPARE(level(), 10);
        display.setBrightness(0.0);
        QCOMPARE(level(), 1);
    }

    void theEffectiveValueIsReported() {
        setLevel(8);
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        QSignalSpy        changed(&display, &DisplayManagerCpp::brightnessChanged);
        display.setBrightness(0.95);
        QCOMPARE(changed.count(), 1);
        QCOMPARE(display.brightness(), 1.0);
        QCOMPARE(display.getBrightness(), 1.0);
    }
};

int main(int argc, char **argv) {
    QProcess bus;
    bus.start(QStringLiteral("dbus-daemon"),
              {QStringLiteral("--session"), QStringLiteral("--nofork"),
               QStringLiteral("--print-address")});
    if (!bus.waitForReadyRead(5000))
        qFatal("no dbus-daemon");
    const QByteArray address = bus.readLine().trimmed();
    // GSD and logind: not the host's.
    qputenv("DBUS_SESSION_BUS_ADDRESS", address);
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", address);
    qputenv("MARATHON_BRIGHTNESS_FLOOR", "0.1");
    QStandardPaths::setTestModeEnabled(true);
    QCoreApplication app(argc, argv);
    TestBrightness   test;
    const int        result = QTest::qExec(&test, argc, argv);
    bus.kill();
    bus.waitForFinished();
    return result;
}

#include "test_brightness.moc"
