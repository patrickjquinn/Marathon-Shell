// clazy:excludeall=qproperty-without-notify (D-Bus properties; QtDBus has no NOTIFY)

#include <QTest>
#include <QSignalSpy>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusUnixFileDescriptor>
#include <QDBusVirtualObject>
#include <QMutex>
#include <QProcess>
#include <QThread>

#include <memory>
#include <poll.h>
#include <unistd.h>

#include "marathon-shell-native/src/power.cxxqt.h"

namespace {

    QByteArray g_bus;

    // logind's Inhibit on a private system bus: each lock is a pipe whose
    // read end tells whether the shell still holds it.
    class FakeLogind : public QObject {
        Q_OBJECT
        Q_CLASSINFO("D-Bus Interface", "org.freedesktop.login1.Manager")

      public:
        struct Lock {
            QString why;
            int     readFd;
        };
        QMutex      mutex;
        QList<Lock> locks;

        ~FakeLogind() override {
            for (const Lock &l : std::as_const(locks))
                ::close(l.readFd);
        }

      public slots:
        QDBusUnixFileDescriptor Inhibit(const QString &, const QString &, const QString &why,
                                        const QString &) {
            int fds[2];
            if (::pipe(fds) != 0)
                return {};
            const QMutexLocker lock(&mutex);
            locks.append({why, fds[0]});
            QDBusUnixFileDescriptor fd(fds[1]);
            ::close(fds[1]);
            return fd;
        }
    };

    // power-profiles-daemon's API, as tuned-ppd serves it.
    class FakePowerProfiles : public QObject {
        Q_OBJECT
        Q_CLASSINFO("D-Bus Interface", "org.freedesktop.UPower.PowerProfiles")
        Q_PROPERTY(QString ActiveProfile READ activeProfile WRITE setActiveProfile)

      public:
        QString activeProfile() const {
            const QMutexLocker lock(&mutex);
            return active;
        }

        void setActiveProfile(const QString &profile) {
            {
                const QMutexLocker lock(&mutex);
                active = profile;
            }
            QDBusMessage changed =
                QDBusMessage::createSignal(QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                                           QStringLiteral("org.freedesktop.DBus.Properties"),
                                           QStringLiteral("PropertiesChanged"));
            changed.setArguments({QStringLiteral("org.freedesktop.UPower.PowerProfiles"),
                                  QVariantMap{{QStringLiteral("ActiveProfile"), profile}},
                                  QStringList()});
            QDBusConnection(QStringLiteral("services")).send(changed);
        }

        mutable QMutex mutex;
        QString        active = QStringLiteral("balanced");
    };

    // systemd's Manager, as much of it as transient units need.
    class FakeSystemd : public QDBusVirtualObject {
      public:
        mutable QMutex mutex;
        QSet<QString>  loaded;
        QStringList    started;
        QStringList    stopped;
        QString        signature;
        bool           refuse = false;

        void           reset() {
            const QMutexLocker lock(&mutex);
            loaded.clear();
            started.clear();
            stopped.clear();
            signature.clear();
            refuse = false;
        }

        QString introspect(const QString &) const override {
            return {};
        }

        bool handleMessage(const QDBusMessage &m, const QDBusConnection &bus) override {
            const QMutexLocker lock(&mutex);
            const QString      unit = m.arguments().value(0).toString();
            const auto fail = [&](const char *error) {
                return bus.send(m.createErrorReply(QString::fromLatin1(error), unit));
            };
            if (m.member() == u"StartTransientUnit") {
                started << unit;
                signature = m.signature();
                if (refuse)
                    return fail("org.freedesktop.DBus.Error.AccessDenied");
                if (loaded.contains(unit))
                    return fail("org.freedesktop.systemd1.UnitExists");
                loaded << unit;
            } else if (m.member() == u"StopUnit") {
                stopped << unit;
                if (!loaded.remove(unit))
                    return fail("org.freedesktop.systemd1.NoSuchUnit");
            } else {
                return false;
            }
            return bus.send(m.createReply(
                QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/freedesktop/systemd1/job/1")))));
        }
    };

    bool held(int readFd) {
        pollfd p{readFd, POLLIN, 0};
        return ::poll(&p, 1, 0) == 0;
    }

} // namespace

class TestPowerManager : public QObject {
    Q_OBJECT

    QThread                            m_serviceThread;
    std::unique_ptr<FakeLogind>        m_logind;
    std::unique_ptr<FakePowerProfiles> m_profiles;
    std::unique_ptr<FakeSystemd>       m_systemd;

    // Sets a wake-up and waits for systemd's answer.
    static bool setTimer(Power &power, const QString &key, qint64 at) {
        QSignalSpy answered(&power, &Power::wakeTimerSet);
        power.setWakeTimer(key, at);
        if (!answered.wait(5000))
            qFatal("systemd did not answer");
        return answered.first().at(1).toBool();
    }

    template <typename T> T systemd(T FakeSystemd::*field) {
        const QMutexLocker lock(&m_systemd->mutex);
        return (*m_systemd).*field;
    }

    bool                               holds(const QString &why) {
        // The fake lives on its own thread; give it the bus round trip.
        QTest::qWait(20);
        const QMutexLocker lock(&m_logind->mutex);
        for (const FakeLogind::Lock &l : std::as_const(m_logind->locks))
            if (l.why == why && held(l.readFd))
                return true;
        return false;
    }

  private slots:
    void initTestCase() {
        m_logind = std::make_unique<FakeLogind>();
        m_logind->moveToThread(&m_serviceThread);
        m_serviceThread.start();
        QDBusConnection services =
            QDBusConnection::connectToBus(QString::fromUtf8(g_bus), QStringLiteral("services"));
        QVERIFY(services.registerObject(QStringLiteral("/org/freedesktop/login1"), m_logind.get(),
                                        QDBusConnection::ExportAllSlots));
        QVERIFY(services.registerService(QStringLiteral("org.freedesktop.login1")));

        m_profiles = std::make_unique<FakePowerProfiles>();
        m_profiles->moveToThread(&m_serviceThread);
        QVERIFY(services.registerObject(QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                                        m_profiles.get(), QDBusConnection::ExportAllProperties));
        QVERIFY(services.registerService(QStringLiteral("org.freedesktop.UPower.PowerProfiles")));

        m_systemd = std::make_unique<FakeSystemd>();
        QVERIFY(services.registerVirtualObject(QStringLiteral("/org/freedesktop/systemd1"),
                                               m_systemd.get()));
        QVERIFY(services.registerService(QStringLiteral("org.freedesktop.systemd1")));
    }

    void init() {
        m_profiles->setActiveProfile(QStringLiteral("balanced"));
        m_systemd->reset();
    }

    void cleanupTestCase() {
        m_serviceThread.quit();
        m_serviceThread.wait();
    }

    void aWakelockLeavesTheLifelongInhibitorHeld() {
        Power power;
        QTRY_VERIFY(holds(QStringLiteral("Handle wake events")));

        QVERIFY(power.acquireWakelock(QStringLiteral("call")));
        QTRY_VERIFY(holds(QStringLiteral("Wakelock: call")));
        QVERIFY(holds(QStringLiteral("Handle wake events")));

        QVERIFY(power.releaseWakelock(QStringLiteral("call")));
        QTRY_VERIFY(!holds(QStringLiteral("Wakelock: call")));
        QVERIFY(holds(QStringLiteral("Handle wake events")));
    }

    void wakelocksAreReleasedOneByOne() {
        Power power;
        QVERIFY(power.acquireWakelock(QStringLiteral("a")));
        QVERIFY(power.acquireWakelock(QStringLiteral("b")));
        QTRY_VERIFY(holds(QStringLiteral("Wakelock: b")));
        QVERIFY(power.releaseWakelock(QStringLiteral("a")));
        QTRY_VERIFY(!holds(QStringLiteral("Wakelock: a")));
        QVERIFY(holds(QStringLiteral("Wakelock: b")));
        QCOMPARE(power.getActiveWakelocks(), QStringList{QStringLiteral("b")});
    }

    void destroyingTheServiceReleasesItsLocks() {
        {
            Power power;
            QVERIFY(power.acquireWakelock(QStringLiteral("gone")));
            QTRY_VERIFY(holds(QStringLiteral("Wakelock: gone")));
        }
        QTRY_VERIFY(!holds(QStringLiteral("Wakelock: gone")));
    }

    void anAlarmIsATimerArmWakeReads() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1792236376));
        QCOMPARE(systemd(&FakeSystemd::started),
                 QStringList{QStringLiteral("marathon-wake-alarm-1792236376.timer")});
        QCOMPARE(systemd(&FakeSystemd::signature), QStringLiteral("ssa(sv)a(sa(sv))"));
    }

    void aNewTimeReplacesTheTimer() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 2000));
        QCOMPARE(systemd(&FakeSystemd::stopped),
                 QStringList{QStringLiteral("marathon-wake-alarm-1000.timer")});
        QCOMPARE(systemd(&FakeSystemd::loaded),
                 QSet<QString>{QStringLiteral("marathon-wake-alarm-2000.timer")});
    }

    void theSameTimeKeepsTheTimer() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QCOMPARE(systemd(&FakeSystemd::started).size(), 1);
        QVERIFY(systemd(&FakeSystemd::stopped).isEmpty());
    }

    void noTimeRemovesTheTimer() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 0));
        QVERIFY(systemd(&FakeSystemd::loaded).isEmpty());
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 0));
        QCOMPARE(systemd(&FakeSystemd::stopped).size(), 1);
    }

    void aTimerLeftByAPreviousShellIsKept() {
        {
            const QMutexLocker lock(&m_systemd->mutex);
            m_systemd->loaded << QStringLiteral("marathon-wake-alarm-1000.timer");
        }
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 2000));
        QCOMPARE(systemd(&FakeSystemd::stopped),
                 QStringList{QStringLiteral("marathon-wake-alarm-1000.timer")});
    }

    void anElapsedTimerIsReplacedQuietly() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        {
            const QMutexLocker lock(&m_systemd->mutex);
            m_systemd->loaded.clear();
        }
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 2000));
        QCOMPARE(systemd(&FakeSystemd::loaded),
                 QSet<QString>{QStringLiteral("marathon-wake-alarm-2000.timer")});
    }

    void aRefusedTimerFailsAndIsRetried() {
        Power power;
        {
            const QMutexLocker lock(&m_systemd->mutex);
            m_systemd->refuse = true;
        }
        QVERIFY(!setTimer(power, QStringLiteral("alarm"), 1000));
        {
            const QMutexLocker lock(&m_systemd->mutex);
            m_systemd->refuse = false;
        }
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QCOMPARE(systemd(&FakeSystemd::started).size(), 2);
    }

    void keysHaveTheirOwnTimers() {
        Power power;
        QVERIFY(setTimer(power, QStringLiteral("alarm"), 1000));
        QVERIFY(setTimer(power, QStringLiteral("app-test"), 1000));
        QCOMPARE(systemd(&FakeSystemd::loaded).size(), 2);
    }

    void aKeyThatIsNoUnitNameIsRefused() {
        Power power;
        QVERIFY(!setTimer(power, QStringLiteral("../x"), 1000));
        QVERIFY(!setTimer(power, QStringLiteral("a b"), 1000));
        QVERIFY(systemd(&FakeSystemd::started).isEmpty());
    }

    void startsFromTheActiveProfile() {
        m_profiles->setActiveProfile(QStringLiteral("performance"));
        Power power;
        QTRY_VERIFY(power.getPowerProfilesSupported());
        QCOMPARE(power.getPowerProfile(), QStringLiteral("performance"));
        QVERIFY(!power.getIsPowerSaveMode());
    }

    void powerSaveSwitchesToThePowerSaverProfileAndBack() {
        Power power;
        QTRY_VERIFY(power.getPowerProfilesSupported());
        power.setPowerSaveMode(true);
        QTRY_COMPARE(m_profiles->activeProfile(), QStringLiteral("power-saver"));
        QVERIFY(power.getIsPowerSaveMode());
        power.setPowerSaveMode(false);
        QTRY_COMPARE(m_profiles->activeProfile(), QStringLiteral("balanced"));
        QTRY_COMPARE(power.getPowerProfile(), QStringLiteral("balanced"));
        QVERIFY(!power.getIsPowerSaveMode());
    }

    void aProfileSetElsewhereIsReported() {
        Power power;
        QTRY_VERIFY(power.getPowerProfilesSupported());
        QSignalSpy saver(&power, &Power::isPowerSaveModeChanged);
        // powerprofilesctl set power-saver
        m_profiles->setActiveProfile(QStringLiteral("power-saver"));
        QTRY_VERIFY(power.getIsPowerSaveMode());
        QCOMPARE(power.getPowerProfile(), QStringLiteral("power-saver"));
        QCOMPARE(saver.count(), 1);
    }
};

int main(int argc, char **argv) {
    QProcess bus;
    bus.start(QStringLiteral("dbus-daemon"),
              {QStringLiteral("--session"), QStringLiteral("--nofork"),
               QStringLiteral("--print-address")});
    if (!bus.waitForReadyRead(5000))
        qFatal("no dbus-daemon");
    g_bus = bus.readLine().trimmed();
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", g_bus);
    qputenv("DBUS_SESSION_BUS_ADDRESS", g_bus);
    QCoreApplication app(argc, argv);
    TestPowerManager test;
    const int        result = QTest::qExec(&test, argc, argv);
    bus.kill();
    bus.waitForFinished();
    return result;
}

#include "test_powermanager.moc"
