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

#include "controllers/displaypolicycontroller.h"
#include "controllers/powerpolicycontroller.h"
#include "managers/displaymanagercpp.h"
#include "services/powerbatteryhandlercpp.h"
#include "services/waketouchfilter.h"

// One screen state: Display1, the power key, the idle timer and Doze all turn
// the same screen on and off, and every consumer reads it.
class TestScreenState : public QObject {
    Q_OBJECT

    QTemporaryDir                            m_sysfs;
    std::unique_ptr<DisplayManagerCpp>       m_display;
    std::unique_ptr<DisplayPolicyController> m_policy;
    std::unique_ptr<PowerPolicyController>   m_power;
    std::unique_ptr<PowerBatteryHandlerCpp>  m_handler;
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
        m_display->setScreenState(on, QStringLiteral("D-Bus Display1.SetScreenState"));
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
        m_display = std::make_unique<DisplayManagerCpp>(nullptr, nullptr, nullptr, m_sysfs.path());
        m_policy  = std::make_unique<DisplayPolicyController>(m_display.get(), nullptr);
        m_power   = std::make_unique<PowerPolicyController>(nullptr, m_display.get());
        m_handler = std::make_unique<PowerBatteryHandlerCpp>(m_power.get(), m_policy.get(),
                                                             m_display.get(), nullptr);
        m_touch   = std::make_unique<WakeTouchFilter>();
        // As main.cpp wires it.
        connect(m_display.get(), &DisplayManagerCpp::screenOnChanged, m_touch.get(),
                &WakeTouchFilter::setScreenOn);
        qApp->installEventFilter(m_touch.get());
    }

    void cleanup() {
        m_touch.reset();
        m_handler.reset();
        m_power.reset();
        m_policy.reset();
        m_display.reset();
    }

    // Power1.StateChanged carries "dozing" on this signal.
    void dozingIsSignalled() {
        QSignalSpy changed(m_power.get(), &PowerPolicyController::dozingChanged);
        dbusSetScreenState(false);
        QCOMPARE(changed.count(), 1);
        dbusSetScreenState(true);
        QCOMPARE(changed.count(), 2);
    }

    void dbusBlankThenWakeLeavesTheShellAwake() {
        dbusSetScreenState(false);
        QCOMPARE(blPower(), QByteArray("4"));
        QVERIFY(!m_display->screenOn());
        QVERIFY(!m_policy->screenOn());
        QVERIFY(m_power->dozing());
        QVERIFY(m_handler->screenOff());

        dbusSetScreenState(true);
        QCOMPARE(blPower(), QByteArray("0"));
        QVERIFY(m_display->screenOn());
        QVERIFY(m_policy->screenOn());
        QVERIFY(!m_power->dozing());
        QVERIFY(!m_handler->screenOff());
        // The next power press turns the screen off rather than "waking" it.
        QCOMPARE(m_power->powerButtonAction(m_policy->screenOn(), false),
                 PowerPolicyController::LockAndTurnScreenOff);
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

    void wakingFromDozeByDbusLeavesDoze() {
        QSignalSpy exited(m_power.get(), &PowerPolicyController::dozeExited);
        m_handler->handlePowerButtonPress(false, true);
        QVERIFY(m_power->dozing());
        m_display->setScreenState(true);
        QVERIFY(!m_power->dozing());
        QCOMPARE(exited.count(), 1);
        QVERIFY(!m_handler->screenOff());
    }

    // wake(reason) is how a call, a message or an alarm turns the screen on.
    void wakingFromDozeLeavesDoze() {
        QVERIFY(m_power->enterDoze(QStringLiteral("power key")));
        QSignalSpy exited(m_power.get(), &PowerPolicyController::dozeExited);
        QSignalSpy waking(m_power.get(), &PowerPolicyController::systemWaking);

        QCOMPARE(m_power->wake(QStringLiteral("alarm")), QStringLiteral("alarm"));
        QVERIFY(!m_power->dozing());
        QCOMPARE(exited.count(), 1);
        QCOMPARE(waking.last().at(0).toString(), QStringLiteral("alarm"));

        QSignalSpy entered(m_power.get(), &PowerPolicyController::dozeEntered);
        m_power->enterDoze(QStringLiteral("power key"));
        QCOMPARE(entered.count(), 1);
    }

    void wakingAnAwakeDeviceDoesNotTouchDoze() {
        QSignalSpy exited(m_power.get(), &PowerPolicyController::dozeExited);
        QSignalSpy waking(m_power.get(), &PowerPolicyController::systemWaking);
        m_power->wake(QStringLiteral("call"));
        QCOMPARE(exited.count(), 0);
        QCOMPARE(waking.count(), 1);
    }

    void anyScreenOffIsDoze() {
        QSignalSpy entered(m_power.get(), &PowerPolicyController::dozeEntered);
        m_policy->turnScreenOff(QStringLiteral("idle timer"));
        QVERIFY(m_power->dozing());
        QCOMPARE(entered.count(), 1);
        m_power->enterDoze(QStringLiteral("power key"));
        QCOMPARE(entered.count(), 1);
        m_power->exitDoze();
        QVERIFY(m_policy->screenOn());
    }

    void reassertingALitScreenIsNotAWake() {
        QSignalSpy wakes(m_policy.get(), &DisplayPolicyController::screenOnChanged);
        QSignalSpy hardware(m_display.get(), &DisplayManagerCpp::screenStateChanged);
        m_display->setScreenState(true);
        m_policy->turnScreenOn();
        QCOMPARE(wakes.count(), 0);
        QCOMPARE(hardware.count(), 2);
    }

    void resumeReportsAWake() {
        QSignalSpy wakes(m_policy.get(), &DisplayPolicyController::screenOnChanged);
        m_policy->forceScreenOn();
        QCOMPARE(wakes.count(), 1);
        m_policy->turnScreenOff();
        wakes.clear();
        m_policy->forceScreenOn();
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
    // Brightness writes go to GSD and logind first: keep them off the host's.
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
