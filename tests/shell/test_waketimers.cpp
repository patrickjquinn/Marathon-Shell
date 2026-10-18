#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QProcess>
#include <QSet>
#include <QTest>

#include "waketimers.h"

// org.freedesktop.systemd1.Manager, as much of it as transient units need.
class FakeSystemd : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.systemd1.Manager")

  public:
    QSet<QString>                     loaded;
    QStringList                       started;
    QStringList                       stopped;
    QHash<QString, SystemdProperties> properties;
    QHash<QString, SystemdAuxUnit>    services;
    bool                              refuse = false;
    QString                           signature;

    void                              reset() {
        loaded.clear();
        started.clear();
        stopped.clear();
        properties.clear();
        services.clear();
        refuse = false;
        signature.clear();
    }

  public slots:
    QDBusObjectPath StartTransientUnit(const QString &name, const QString &mode,
                                       const SystemdProperties     &props,
                                       const QList<SystemdAuxUnit> &aux) {
        Q_UNUSED(mode);
        started << name;
        signature = message().signature();
        if (refuse) {
            sendErrorReply(QStringLiteral("org.freedesktop.DBus.Error.AccessDenied"), "no");
            return {};
        }
        if (loaded.contains(name)) {
            sendErrorReply(QStringLiteral("org.freedesktop.systemd1.UnitExists"), "exists");
            return {};
        }
        loaded << name;
        properties.insert(name, props);
        if (!aux.isEmpty())
            services.insert(name, aux.first());
        return QDBusObjectPath("/org/freedesktop/systemd1/job/1");
    }
    QDBusObjectPath StopUnit(const QString &name, const QString &mode) {
        Q_UNUSED(mode);
        stopped << name;
        if (!loaded.remove(name)) {
            sendErrorReply(QStringLiteral("org.freedesktop.systemd1.NoSuchUnit"), "none");
            return {};
        }
        return QDBusObjectPath("/org/freedesktop/systemd1/job/2");
    }
};

class TestWakeTimers : public QObject {
    Q_OBJECT

    QProcess        daemon;
    QString         address;
    FakeSystemd    *systemd = nullptr;
    QDBusConnection client{QString()};

    static QVariant value(const SystemdProperties &props, const QString &name) {
        for (const SystemdProperty &p : props)
            if (p.name == name)
                return p.value.variant();
        return {};
    }

    // Sets a timer and waits for systemd's answer.
    bool set(WakeTimers &timers, const QString &key, qint64 at) {
        bool answered = false;
        bool ok       = false;
        timers.set(key, at, [&](bool result) {
            answered = true;
            ok       = result;
        });
        if (!QTest::qWaitFor([&] { return answered; }, 5000))
            qFatal("systemd did not answer");
        return ok;
    }

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        WakeTimers::registerTypes();
        QDBusConnection manager = QDBusConnection::connectToBus(address, "systemd");
        systemd                 = new FakeSystemd;
        QVERIFY(manager.registerObject("/org/freedesktop/systemd1", systemd,
                                       QDBusConnection::ExportAllSlots));
        QVERIFY(manager.registerService("org.freedesktop.systemd1"));
        client = QDBusConnection::connectToBus(address, "shell");
        QVERIFY(client.isConnected());
    }
    void init() {
        systemd->reset();
    }
    void cleanupTestCase() {
        delete systemd;
        daemon.kill();
        daemon.waitForFinished();
    }

    void anAlarmIsATimerArmWakeReads() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1792236376));
        const QString unit = "marathon-wake-alarm-1792236376.timer";
        QCOMPARE(systemd->started, QStringList{unit});
        QCOMPARE(systemd->signature, "ssa(sv)a(sa(sv))");
        QCOMPARE(value(systemd->properties[unit], "OnCalendar").toString(), "@1792236376");
        QCOMPARE(value(systemd->properties[unit], "RemainAfterElapse").toBool(), false);

        const SystemdAuxUnit service = systemd->services[unit];
        QCOMPARE(service.name, "marathon-wake-alarm-1792236376.service");
        const auto execStart = value(service.properties, "ExecStart").value<QDBusArgument>();
        QCOMPARE(execStart.currentSignature(), "a(sasb)");
        const auto exec = qdbus_cast<QList<SystemdExecCommand>>(execStart);
        QCOMPARE(exec.size(), 1);
        QCOMPARE(exec.first().path, "/bin/true");
    }

    void aNewTimeReplacesTheTimer() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        QVERIFY(set(timers, "alarm", 2000));
        QTRY_COMPARE(systemd->stopped, QStringList{"marathon-wake-alarm-1000.timer"});
        QCOMPARE(systemd->loaded, QSet<QString>{"marathon-wake-alarm-2000.timer"});
    }

    void theSameTimeKeepsTheTimer() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        QVERIFY(set(timers, "alarm", 1000));
        QCOMPARE(systemd->started.size(), 1);
        QVERIFY(systemd->stopped.isEmpty());
    }

    void noTimeRemovesTheTimer() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        QVERIFY(set(timers, "alarm", 0));
        QTRY_VERIFY(systemd->loaded.isEmpty());
        QVERIFY(set(timers, "alarm", 0));
        QCOMPARE(systemd->stopped.size(), 1);
    }

    void aTimerLeftByAPreviousShellIsKept() {
        systemd->loaded << "marathon-wake-alarm-1000.timer";
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        QVERIFY(set(timers, "alarm", 2000));
        QTRY_COMPARE(systemd->stopped, QStringList{"marathon-wake-alarm-1000.timer"});
    }

    void anElapsedTimerIsReplacedQuietly() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        systemd->loaded.clear();
        QVERIFY(set(timers, "alarm", 2000));
        QCOMPARE(systemd->loaded, QSet<QString>{"marathon-wake-alarm-2000.timer"});
    }

    void aRefusedTimerFailsAndIsRetried() {
        WakeTimers timers(client);
        systemd->refuse = true;
        QVERIFY(!set(timers, "alarm", 1000));
        systemd->refuse = false;
        QVERIFY(set(timers, "alarm", 1000));
        QCOMPARE(systemd->started.size(), 2);
    }

    void keysHaveTheirOwnTimers() {
        WakeTimers timers(client);
        QVERIFY(set(timers, "alarm", 1000));
        QVERIFY(set(timers, "app-test", 1000));
        QCOMPARE(systemd->loaded.size(), 2);
    }

    void aKeyThatIsNoUnitNameIsRefused() {
        WakeTimers timers(client);
        QVERIFY(!set(timers, "../x", 1000));
        QVERIFY(!set(timers, "a b", 1000));
        QVERIFY(systemd->started.isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestWakeTimers)
#include "test_waketimers.moc"
