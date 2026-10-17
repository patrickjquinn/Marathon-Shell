#include <QtTest>
#include <QDBusConnection>
#include <QDBusUnixFileDescriptor>
#include <QMutex>
#include <QProcess>
#include <QThread>

#include <memory>
#include <poll.h>
#include <unistd.h>

#include "managers/powermanagercpp.h"

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

    bool held(int readFd) {
        pollfd p{readFd, POLLIN, 0};
        return ::poll(&p, 1, 0) == 0;
    }

} // namespace

class TestPowerManager : public QObject {
    Q_OBJECT

    QThread                     m_serviceThread;
    std::unique_ptr<FakeLogind> m_logind;

    bool                        holds(const QString &why) {
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
    }

    void cleanupTestCase() {
        m_serviceThread.quit();
        m_serviceThread.wait();
    }

    void aWakelockLeavesTheLifelongInhibitorHeld() {
        PowerManagerCpp power;
        QVERIFY(holds(QStringLiteral("Handle wake events")));

        QVERIFY(power.acquireWakelock(QStringLiteral("call")));
        QVERIFY(holds(QStringLiteral("Wakelock: call")));
        QVERIFY(holds(QStringLiteral("Handle wake events")));

        QVERIFY(power.releaseWakelock(QStringLiteral("call")));
        QVERIFY(!holds(QStringLiteral("Wakelock: call")));
        QVERIFY(holds(QStringLiteral("Handle wake events")));
    }

    void wakelocksAreReleasedOneByOne() {
        PowerManagerCpp power;
        QVERIFY(power.acquireWakelock(QStringLiteral("a")));
        QVERIFY(power.acquireWakelock(QStringLiteral("b")));
        QVERIFY(power.releaseWakelock(QStringLiteral("a")));
        QVERIFY(!holds(QStringLiteral("Wakelock: a")));
        QVERIFY(holds(QStringLiteral("Wakelock: b")));
        QCOMPARE(power.activeWakelocks(), QStringList{QStringLiteral("b")});
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
