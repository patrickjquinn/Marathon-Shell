// clazy:excludeall=qproperty-without-notify (D-Bus properties; QtDBus has no NOTIFY)

#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QSemaphore>
#include <QSignalSpy>
#include <QTest>
#include <QThread>

#include "mpris2controller.h"

namespace {
    // NOLINTBEGIN(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString kPath   = QStringLiteral("/org/mpris/MediaPlayer2");
    const QString kPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
    // NOLINTEND(bugprone-throwing-static-initialization)
}

class RootAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
  public:
    explicit RootAdaptor(QObject *parent)
        : QDBusAbstractAdaptor(parent) {}
    QString identity() const {
        return "Shortwave";
    }
    QString desktopEntry() const {
        return "de.haeckerfelix.Shortwave";
    }
};

class PlayerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus MEMBER status)
    Q_PROPERTY(QVariantMap Metadata MEMBER metadata)
    Q_PROPERTY(bool CanPlay MEMBER canPlay)
    Q_PROPERTY(bool CanPause MEMBER canPause)
    Q_PROPERTY(bool CanGoNext MEMBER canGoNext)
    Q_PROPERTY(bool CanGoPrevious MEMBER canGoPrevious)
    Q_PROPERTY(bool CanSeek MEMBER canSeek)
    Q_PROPERTY(qlonglong Position MEMBER position)
  public:
    explicit PlayerAdaptor(QObject *parent)
        : QDBusAbstractAdaptor(parent) {}
    QString     status = "Playing";
    QVariantMap metadata{{"xesam:artist", QStringList{"CJME News/Talk 980"}},
                         {"mpris:artUrl", "file:///tmp/cjme.png"}};
    bool        canPlay = true, canPause = true, canGoNext = false, canGoPrevious = false,
         canSeek = false;
    qlonglong   position  = 0;
    int         playPauses = 0;
  public slots:
    void PlayPause() {
        ++playPauses;
    }
};

class FakePlayer : public QObject {
    Q_OBJECT
  public:
    explicit FakePlayer(const QString &connectionName)
        : root(new RootAdaptor(this))
        , player(new PlayerAdaptor(this))
        , bus(QDBusConnection::connectToBus(QDBusConnection::SessionBus, connectionName)) {}

    bool publish(const QString &service) {
        return bus.registerObject(kPath, this, QDBusConnection::ExportAdaptors) &&
            bus.registerService(service);
    }

    void changed(const QVariantMap &props) const {
        QDBusMessage s =
            QDBusMessage::createSignal(kPath, "org.freedesktop.DBus.Properties", "PropertiesChanged");
        s << kPlayer << props << QStringList();
        bus.send(s);
    }

    RootAdaptor    *root;
    PlayerAdaptor  *player;
    QDBusConnection bus;
};

// Lives in a thread that is stuck, as a GTK player is while it waits on
// the compositor: calls to it are never answered.
class HungThread : public QThread {
  public:
    QSemaphore release;
    QObject   *object = nullptr;
    QThread   *home   = nullptr;
    void       run() override {
        release.acquire();
        object->moveToThread(home);
    }
};

class TestMPRIS2Controller : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase() {
        if (!QDBusConnection::sessionBus().isConnected())
            QSKIP("no session bus");
    }

    void followsAPlayer() {
        FakePlayer p("player");
        QVERIFY(p.publish("org.mpris.MediaPlayer2.Shortwave"));
        MPRIS2Controller c;
        QTRY_VERIFY(c.hasActivePlayer());
        QCOMPARE(c.playerName(), QString("Shortwave"));
        QCOMPARE(c.desktopEntry(), QString("de.haeckerfelix.Shortwave"));
        QVERIFY(c.isPlaying());
        QCOMPARE(c.trackTitle(), QString());
        QCOMPARE(c.trackArtist(), QString("CJME News/Talk 980"));
        QCOMPARE(c.albumArtUrl(), QString("file:///tmp/cjme.png"));
        QVERIFY(c.canPause());
        QVERIFY(!c.canGoNext());

        c.playPause();
        QTRY_COMPARE(p.player->playPauses, 1);

        p.player->status    = "Paused";
        p.player->canGoNext = true;
        p.changed({{"PlaybackStatus", "Paused"}, {"CanGoNext", true}});
        QTRY_VERIFY(c.isPaused());
        QVERIFY(c.canGoNext());

        // Another client's player on the same path is not ours.
        FakePlayer other("other");
        other.changed({{"PlaybackStatus", "Playing"}});
        QTest::qWait(200);
        QVERIFY(c.isPaused());

        p.player->metadata = {{"xesam:title", "Headlines"}, {"xesam:artist", QStringList{"CJME"}}};
        p.changed({{"Metadata", p.player->metadata}});
        QTRY_COMPARE(c.trackTitle(), QString("Headlines"));
        QCOMPARE(c.trackArtist(), QString("CJME"));

        QSignalSpy gone(&c, &MPRIS2Controller::activePlayerChanged);
        p.bus.unregisterService("org.mpris.MediaPlayer2.Shortwave");
        QTRY_VERIFY(!c.hasActivePlayer());
        QVERIFY(gone.count() >= 1);
    }

    void adoptsAPlayerThatAppearsLater() {
        MPRIS2Controller c;
        QTest::qWait(100);
        QVERIFY(!c.hasActivePlayer());
        FakePlayer p("late");
        QVERIFY(p.publish("org.mpris.MediaPlayer2.Late"));
        QTRY_VERIFY(c.hasActivePlayer());
        p.bus.unregisterService("org.mpris.MediaPlayer2.Late");
        QTRY_VERIFY(!c.hasActivePlayer());
    }

    // The shell froze for minutes behind a player that would not answer.
    void aHungPlayerNeverBlocksTheGuiThread() {
        HungThread thread;
        FakePlayer p("hung");
        QVERIFY(p.publish("org.mpris.MediaPlayer2.Hung"));
        thread.object = &p;
        thread.home   = QThread::currentThread();
        p.moveToThread(&thread);
        thread.start();

        QElapsedTimer t;
        t.start();
        MPRIS2Controller c;
        c.playPause();
        c.next();
        c.scanForPlayers();
        QVERIFY2(t.elapsed() < 200, qPrintable(QString::number(t.elapsed())));

        int    ticks = 0;
        QTimer tick;
        connect(&tick, &QTimer::timeout, this, [&] { ++ticks; });
        tick.start(10);
        QTest::qWait(1000);
        QVERIFY2(ticks > 50, qPrintable(QString::number(ticks)));
        QVERIFY(!c.hasActivePlayer());

        thread.release.release();
        thread.wait();
    }
};

QTEST_GUILESS_MAIN(TestMPRIS2Controller)
#include "test_mpris2controller.moc"
