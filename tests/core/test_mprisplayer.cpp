#include <QtTest>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QSignalSpy>

#include "MprisPlayer.h"

namespace {
    const QString kService = QStringLiteral("org.mpris.MediaPlayer2.music");
    const QString kPath    = QStringLiteral("/org/mpris/MediaPlayer2");
}

class PropertiesWatcher : public QObject {
    Q_OBJECT
  public:
    QList<QVariantMap> changes;
  public slots:
    void onChanged(const QString &, const QVariantMap &changed, const QStringList &) {
        changes.append(changed);
    }
};

class TestMprisPlayer : public QObject {
    Q_OBJECT

  private:
    static QVariant get(const QString &interface, const QString &name) {
        QDBusInterface props(kService, kPath, "org.freedesktop.DBus.Properties");
        QDBusReply<QDBusVariant> r = props.call("Get", interface, name);
        return r.isValid() ? r.value().variant() : QVariant();
    }

    static bool onBus() {
        return QDBusConnection::sessionBus().interface()->isServiceRegistered(kService);
    }

    static void make(MprisPlayer &player) {
        player.setProperty("title", "Dawn");
        player.setProperty("artist", "Bo");
        player.setProperty("album", "Ice");
        player.setProperty("length", 30000);
        player.setProperty("trackId", 3);
        player.setProperty("canGoNext", true);
        player.classBegin();
        player.componentComplete();
    }

  private slots:
    void initTestCase() {
        if (!QDBusConnection::sessionBus().isConnected())
            QSKIP("no session bus");
    }

    void publishesOnlyWhileActive() {
        MprisPlayer player;
        make(player);
        QVERIFY(!onBus());
        player.setProperty("active", true);
        QVERIFY(player.property("registered").toBool());
        QVERIFY(onBus());
        player.setProperty("active", false);
        QVERIFY(!onBus());
    }

    void exposesStatusAndMetadata() {
        MprisPlayer player;
        make(player);
        player.setProperty("active", true);
        const QString iface = "org.mpris.MediaPlayer2.Player";
        QCOMPARE(get("org.mpris.MediaPlayer2", "Identity").toString(), QStringLiteral("Music"));
        QCOMPARE(get("org.mpris.MediaPlayer2", "DesktopEntry").toString(), QStringLiteral("music"));
        QCOMPARE(get(iface, "PlaybackStatus").toString(), QStringLiteral("Paused"));
        QVERIFY(get(iface, "CanGoNext").toBool());
        QVERIFY(!get(iface, "CanGoPrevious").toBool());

        const QDBusArgument arg  = get(iface, "Metadata").value<QDBusArgument>();
        QVariantMap         meta;
        arg >> meta;
        QCOMPARE(meta.value("xesam:title").toString(), QStringLiteral("Dawn"));
        QCOMPARE(meta.value("xesam:artist").toStringList(), QStringList{"Bo"});
        QCOMPARE(meta.value("mpris:length").toLongLong(), 30000000LL);

        player.setProperty("position", 1500);
        QCOMPARE(get(iface, "Position").toLongLong(), 1500000LL);
    }

    void announcesChanges() {
        MprisPlayer player;
        make(player);
        player.setProperty("active", true);
        PropertiesWatcher watcher;
        QVERIFY(QDBusConnection::sessionBus().connect(
            kService, kPath, "org.freedesktop.DBus.Properties", "PropertiesChanged", &watcher,
            SLOT(onChanged(QString, QVariantMap, QStringList))));
        player.setProperty("playing", true);
        QTRY_VERIFY(!watcher.changes.isEmpty());
        QCOMPARE(watcher.changes.last().value("PlaybackStatus").toString(), QStringLiteral("Playing"));
    }

    void forwardsControls() {
        MprisPlayer player;
        make(player);
        player.setProperty("active", true);
        player.setProperty("position", 10000);
        QSignalSpy     playPause(&player, &MprisPlayer::playPauseRequested);
        QSignalSpy     next(&player, &MprisPlayer::nextRequested);
        QSignalSpy     seek(&player, &MprisPlayer::seekRequested);
        QSignalSpy     repeat(&player, &MprisPlayer::repeatModeRequested);
        QDBusInterface iface(kService, kPath, "org.mpris.MediaPlayer2.Player");
        iface.call("PlayPause");
        iface.call("Next");
        iface.call("Seek", qlonglong(5000000));
        iface.call("SetPosition", QVariant::fromValue(QDBusObjectPath("/org/marathonos/music/track/3")),
                   qlonglong(2000000));
        iface.call("SetPosition", QVariant::fromValue(QDBusObjectPath("/org/marathonos/music/track/9")),
                   qlonglong(2000000));
        iface.call("Seek", qlonglong(60000000));
        QDBusInterface props(kService, kPath, "org.freedesktop.DBus.Properties");
        props.call("Set", "org.mpris.MediaPlayer2.Player", "LoopStatus",
                   QVariant::fromValue(QDBusVariant(QStringLiteral("Track"))));
        QCOMPARE(playPause.size(), 1);
        QCOMPARE(next.size(), 2);
        QCOMPARE(seek.size(), 2);
        QCOMPARE(seek.at(0).at(0).toLongLong(), 15000LL);
        QCOMPARE(seek.at(1).at(0).toLongLong(), 2000LL);
        QCOMPARE(repeat.size(), 1);
        QCOMPARE(repeat.at(0).at(0).toString(), QStringLiteral("one"));
    }
};

QTEST_GUILESS_MAIN(TestMprisPlayer)
#include "test_mprisplayer.moc"
