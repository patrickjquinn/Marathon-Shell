// clazy:excludeall=qproperty-without-notify (D-Bus properties; QtDBus has no NOTIFY)

#include <QTest>
#include <QSignalSpy>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>

#include "managers/displaymanagercpp.h"
#include "managers/sensormanagercpp.h"

namespace {

    QByteArray g_bus;

    // iio-sensor-proxy on a device with sensors but no light sensor.
    class FakeSensorProxy : public QObject {
        Q_OBJECT
        Q_CLASSINFO("D-Bus Interface", "net.hadess.SensorProxy")
        Q_PROPERTY(bool HasAmbientLight READ hasAmbientLight)
        Q_PROPERTY(bool HasAccelerometer READ hasAccelerometer)

      public:
        bool hasAmbientLight() const {
            return false;
        }
        bool hasAccelerometer() const {
            return true;
        }

      public slots:
        void ClaimLight() {}
        void ReleaseLight() {}
    };

} // namespace

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

    QString backlightDir() const {
        return m_sysfs.filePath(QStringLiteral("backlight"));
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

    void noLightSensorMeansNoAutoBrightness() {
        SensorManagerCpp sensors(nullptr, m_sysfs.filePath(QStringLiteral("iio-none")));
        QVERIFY(!sensors.lightAvailable());
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        display.setSensorManager(&sensors);
        display.setAutoBrightness(true);
        QVERIFY(!display.lightSensorAvailable());
        QVERIFY(!display.autoBrightnessEnabled());
    }

    void aLightSensorMakesAutoBrightnessAvailable() {
        SensorManagerCpp sensors(nullptr, m_sysfs.filePath(QStringLiteral("iio-light")));
        QVERIFY(sensors.lightAvailable());
        DisplayManagerCpp display(nullptr, nullptr, nullptr, backlightDir());
        display.setSensorManager(&sensors);
        display.setAutoBrightness(true);
        QVERIFY(display.autoBrightnessEnabled());
        display.setAutoBrightness(false);
    }

    void aSensorProxyWithoutALightSensorIsNoLightSensor() {
        QThread         thread;
        FakeSensorProxy proxy;
        proxy.moveToThread(&thread);
        thread.start();
        QDBusConnection services =
            QDBusConnection::connectToBus(QString::fromUtf8(g_bus), QStringLiteral("services"));
        QVERIFY(services.registerObject(QStringLiteral("/net/hadess/SensorProxy"), &proxy,
                                        QDBusConnection::ExportAllProperties |
                                            QDBusConnection::ExportAllSlots));
        QVERIFY(services.registerService(QStringLiteral("net.hadess.SensorProxy")));

        SensorManagerCpp sensors(nullptr, m_sysfs.filePath(QStringLiteral("iio-none")));
        QVERIFY(!sensors.lightAvailable());

        services.unregisterService(QStringLiteral("net.hadess.SensorProxy"));
        services.unregisterObject(QStringLiteral("/net/hadess/SensorProxy"));
        thread.quit();
        thread.wait();
    }
};

int main(int argc, char **argv) {
    QProcess bus;
    bus.start(QStringLiteral("dbus-daemon"),
              {QStringLiteral("--session"), QStringLiteral("--nofork"),
               QStringLiteral("--print-address")});
    if (!bus.waitForReadyRead(5000))
        qFatal("no dbus-daemon");
    g_bus                    = bus.readLine().trimmed();
    const QByteArray address = g_bus;
    // GSD, logind and iio-sensor-proxy: none of the host's.
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
