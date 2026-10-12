#include <QtTest>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QTemporaryDir>
#include <QWindow>
#include <QCloseEvent>

#include "keelhost.h"

static const char *kPath  = "/org/shipwright/keel/Shell";
static const char *kIface = "org.shipwright.keel.Shell1";

class TestKeelHost : public QObject {
    Q_OBJECT

    QTemporaryDir runtime;
    QVariantMap   m_last;
    int           m_coverStatus = -1;

    static QDBusConnection peer(const QString &address, const QString &name) {
        return QDBusConnection::connectToPeer(address, name);
    }

    // Asynchronous, with the event loop running: the host is served from
    // this same thread, so a blocking call would deadlock.
    static QVariant call(QDBusConnection &bus, const QString &iface, const QString &method,
                         const QVariantList &args = {}) {
        QDBusMessage msg = QDBusMessage::createMethodCall(QString(), kPath, iface, method);
        msg.setArguments(args);
        QDBusPendingCall pending = bus.asyncCall(msg, 5000);
        QDeadlineTimer deadline(5000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(10);
        QVariant v = pending.reply().arguments().value(0);
        if (v.canConvert<QDBusVariant>())
            v = v.value<QDBusVariant>().variant();
        if (v.canConvert<QDBusArgument>())
            v = qdbus_cast<QVariantMap>(v.value<QDBusArgument>());
        return v;
    }

    static QVariant property(QDBusConnection &bus, const QString &name) {
        return call(bus, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"),
                    {QString::fromLatin1(kIface), name});
    }

  public slots:
    void onCoverStatus(int status) {
        m_coverStatus = status;
    }
    void onAmbience(const QVariantMap &m) {
        m_last = m;
    }

  private slots:
    void environmentFollowsProtocol() {
        KeelHost host(144);
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#00ffaa"},
                          {"/desktop/jolla/theme/color_scheme", "lightondark"}});
        QVERIFY(host.start(runtime.path()));
        const auto env = host.environment();
        QCOMPARE(env.value("KEEL_SHELL"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_PROTOCOL"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_DBUS"), host.address());
        QCOMPARE(env.value("KEEL_SHELL_COVER_ENABLED"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_DPI"), QStringLiteral("144"));
        QCOMPARE(env.value("KEEL_AMBIENCE_COLOR_HIGHLIGHT"), QStringLiteral("#00ffaa"));
        QCOMPARE(env.value("KEEL_AMBIENCE_COLOR_SCHEME"), QStringLiteral("lightondark"));
        QVERIFY(env.value("KEEL_AMBIENCE_KEYS")
                    .split(':')
                    .contains(QStringLiteral("/desktop/jolla/theme/color/highlight")));
    }

    void emptyAmbienceExportsNoAmbienceKeys() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QVERIFY(!host.environment().contains("KEEL_AMBIENCE_KEYS"));
    }

    void peerCanPingAndReadProperties() {
        KeelHost host(144);
        host.setActive(true);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t1");
        QTRY_VERIFY(bus.isConnected());
        QCOMPARE(call(bus, kIface, "Ping").toString(), QStringLiteral("marathon"));
        QCOMPARE(property(bus, "ProtocolVersion").toInt(), 1);
        QCOMPARE(property(bus, "Active").toBool(), true);
        QDBusConnection::disconnectFromPeer("t1");
    }

    void coverStatusReachesPeer() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "tc");
        QTRY_VERIFY(bus.isConnected());
        QVERIFY(bus.connect(QString(), kPath, kIface, "CoverStatusChanged", this,
                            SLOT(onCoverStatus(int))));
        QCOMPARE(call(bus, kIface, "Ping").toString(), QStringLiteral("marathon"));
        QCOMPARE(property(bus, "CoverStatus").toInt(), 0);
        host.setCoverStatus(1);
        QTRY_COMPARE(m_coverStatus, 1);
        QCOMPARE(property(bus, "CoverStatus").toInt(), 1);
        m_coverStatus = -1;
        host.setCoverStatus(1);
        QTest::qWait(100);
        QCOMPARE(m_coverStatus, -1);
        QDBusConnection::disconnectFromPeer("tc");
    }

    void ambienceChangeReachesPeer() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t2");
        QTRY_VERIFY(bus.isConnected());
        QVERIFY(bus.connect(QString(), kPath, kIface, "AmbienceChanged", this,
                            SLOT(onAmbience(QVariantMap))));
        QCOMPARE(call(bus, kIface, "Ping").toString(), QStringLiteral("marathon"));
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#123456"}});
        QTRY_COMPARE(m_last.value("/desktop/jolla/theme/color/highlight").toString(),
                     QStringLiteral("#123456"));
        QDBusConnection::disconnectFromPeer("t2");
    }

    void survivesPeerDisconnect() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        {
            QDBusConnection bus = peer(host.address(), "t3");
            QTRY_VERIFY(bus.isConnected());
            QDBusConnection::disconnectFromPeer("t3");
        }
        QTest::qWait(100);
        host.setActive(true);
        host.setAmbience({{"/desktop/jolla/theme/color_scheme", "darkonlight"}});
        host.requestClose();
    }

    void activateCallRunsCallback() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t4");
        QTRY_VERIFY(bus.isConnected());
        int activations = 0;
        host.onActivate = [&activations]() { ++activations; };
        call(bus, kIface, "Activate");
        QTRY_COMPARE(activations, 1);
        QDBusConnection::disconnectFromPeer("t4");
    }

    void leavesNothingInTheRuntimeDir() {
        QTemporaryDir dir;
        {
            KeelHost host(144);
            QVERIFY(host.start(dir.path()));
            KeelHost other(144);
            QVERIFY(other.start(dir.path()));
            QVERIFY(host.address() != other.address());
        }
        QCOMPARE(QDir(dir.path()).entryList(QDir::AllEntries | QDir::NoDotAndDotDot), QStringList());
    }

    void firstWindowCloseBecomesCloseRequested() {
        QWindow window;
        int    requests = 0;
        KeelCloseGuard guard([&requests]() { ++requests; });
        window.installEventFilter(&guard);

        QCloseEvent first;
        QCoreApplication::sendEvent(&window, &first);
        QVERIFY(!first.isAccepted());
        QCOMPARE(requests, 1);

        QCloseEvent second;
        QCoreApplication::sendEvent(&window, &second);
        QCOMPARE(requests, 1);
    }

    void lateAmbienceStillReachesPeers() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QVERIFY(!host.environment().contains("KEEL_AMBIENCE_KEYS"));
        QDBusConnection bus = peer(host.address(), "t5");
        QTRY_VERIFY(bus.isConnected());
        QVERIFY(bus.connect(QString(), kPath, kIface, "AmbienceChanged", this,
                            SLOT(onAmbience(QVariantMap))));
        QCOMPARE(call(bus, kIface, "Ping").toString(), QStringLiteral("marathon"));
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#abcdef"}});
        QTRY_COMPARE(m_last.value("/desktop/jolla/theme/color/highlight").toString(),
                     QStringLiteral("#abcdef"));
        QCOMPARE(property(bus, "Ambience").toMap().value("/desktop/jolla/theme/color/highlight").toString(),
                 QStringLiteral("#abcdef"));
        QDBusConnection::disconnectFromPeer("t5");
    }
};

QTEST_MAIN(TestKeelHost)
#include "test_keelhost.moc"
