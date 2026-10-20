#include <QTest>
#include <QSignalSpy>
#include <QGuiApplication>
#include <QPointingDevice>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTemporaryDir>

#include <memory>

#include "marathon-shell-native/src/display.cxxqt.h"
#include "services/waketouchfilter.h"

// One screen state: Display1, the power key, the idle timer and Doze all turn
// the same screen on and off, and every consumer reads it.
class TestScreenState : public QObject {
    Q_OBJECT

    QTemporaryDir                            m_sysfs;
    std::unique_ptr<marathon::Display>                 m_display;
    std::unique_ptr<WakeTouchFilter>         m_touch;
    QPointingDevice                         *m_device = nullptr;

    static void                              write(const QString &path, const QByteArray &value) {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
        f.write(value);
    }

    QByteArray blPower() const {
        QFile f(m_sysfs.filePath(QStringLiteral("panel/bl_power")));
        return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed() : QByteArray();
    }

    // What Display1.SetScreenState runs.
    void dbusSetScreenState(bool on) {
        if (on)
            m_display->turnScreenOn();
        else
            m_display->turnScreenOff(QStringLiteral("D-Bus Display1.SetScreenState"));
    }

    void tap(QQuickWindow *scene) {
        QTest::touchEvent(scene, m_device).press(0, QPoint(10, 10));
        QTest::touchEvent(scene, m_device).release(0, QPoint(10, 10));
    }

  private slots:
    void initTestCase() {
        m_device = QTest::createTouchDevice();
        QVERIFY(m_sysfs.isValid());
        QVERIFY(QDir(m_sysfs.path()).mkpath(QStringLiteral("panel")));
    }

    void init() {
        write(m_sysfs.filePath(QStringLiteral("panel/max_brightness")), "10\n");
        write(m_sysfs.filePath(QStringLiteral("panel/brightness")), "5\n");
        write(m_sysfs.filePath(QStringLiteral("panel/actual_brightness")), "5\n");
        write(m_sysfs.filePath(QStringLiteral("panel/bl_power")), "0\n");
        m_display = std::make_unique<marathon::Display>();
        m_display->start(m_sysfs.path(), m_sysfs.filePath(QStringLiteral("no-iio")), 0.28);
        m_touch   = std::make_unique<WakeTouchFilter>();
        // As main.cpp wires it.
        connect(m_display.get(), &marathon::Display::screenOnChanged, m_touch.get(),
                [this] { m_touch->setScreenOn(m_display->getScreenOn()); });
        qApp->installEventFilter(m_touch.get());
    }

    void cleanup() {
        m_touch.reset();
        m_display.reset();
    }

    void dbusBlankThenWakeLeavesTheShellAwake() {
        dbusSetScreenState(false);
        QCOMPARE(blPower(), QByteArray("4"));
        QVERIFY(!m_display->getScreenOn());

        dbusSetScreenState(true);
        QTRY_COMPARE(blPower(), QByteArray("0"));
        QVERIFY(m_display->getScreenOn());
    }

    void touchWorksAgainAfterDbusBlankAndWake() {
        QQmlEngine    engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\n"
                          "Window { width: 100; height: 100; visible: true\n"
                          "  property int taps: 0\n"
                          "  MouseArea { anchors.fill: parent; onClicked: taps++ } }",
                          QUrl());
        std::unique_ptr<QObject> created(component.create());
        auto                    *scene = qobject_cast<QQuickWindow *>(created.get());
        QVERIFY2(scene, qPrintable(component.errorString()));
        QVERIFY(QTest::qWaitForWindowExposed(scene));

        // The tap that blanks lands with the finger still down; the wake comes
        // while a second finger is on the glass.
        QTest::touchEvent(scene, m_device).press(0, QPoint(10, 10));
        dbusSetScreenState(false);
        QTest::touchEvent(scene, m_device).release(0, QPoint(10, 10));
        tap(scene);
        QTest::touchEvent(scene, m_device).press(0, QPoint(10, 10));
        dbusSetScreenState(true);
        QTest::touchEvent(scene, m_device).release(0, QPoint(10, 10));
        QTest::qWait(WakeTouchFilter::BlockMs + 20);

        const int before = scene->property("taps").toInt();
        tap(scene);
        tap(scene);
        QCOMPARE(scene->property("taps").toInt(), before + 2);
    }

    void reassertingALitScreenIsNotAWake() {
        QSignalSpy wakes(m_display.get(), &marathon::Display::screenOnChanged);
        QSignalSpy hardware(m_display.get(), &marathon::Display::screenStateChanged);
        m_display->turnScreenOn();
        m_display->turnScreenOn();
        QCOMPARE(wakes.count(), 0);
        QCOMPARE(hardware.count(), 2);
    }

    void resumeReportsAWake() {
        QSignalSpy wakes(m_display.get(), &marathon::Display::screenOnChanged);
        m_display->forceScreenOn();
        QCOMPARE(wakes.count(), 1);
        m_display->turnScreenOff(QStringLiteral("test"));
        wakes.clear();
        m_display->forceScreenOn();
        QCOMPARE(wakes.count(), 1);
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
    // logind sets brightness when sysfs is not writable: keep it off the host's.
    qputenv("DBUS_SESSION_BUS_ADDRESS", address);
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", address);
    qputenv("MARATHON_WIFI_POWERSAVE", "0");
    QGuiApplication app(argc, argv);
    TestScreenState test;
    const int       result = QTest::qExec(&test, argc, argv);
    bus.kill();
    bus.waitForFinished();
    return result;
}

#include "test_screenstate.moc"
