// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Amber.Mpris (amber-mpris for Qt 6) on a private session bus: an
// MprisPlayer publishes org.mpris.MediaPlayer2.<name> with its status and
// metadata, which a plain D-Bus MPRIS client (as Lipstick's media controls
// are) reads, and the client's calls reach the QML handlers; an
// MprisController follows a player another process (here: a plain D-Bus
// service) publishes, and its commands reach that player.

#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusVariant>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTest>
#include <memory>

namespace {

// A player in the D-Bus sense only: org.mpris.MediaPlayer2 and its Player
// interface on a connection of its own, as another app's player would be.
class FakePlayerRoot : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(bool CanQuit READ no)
    Q_PROPERTY(bool CanRaise READ no)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ empty)
    Q_PROPERTY(QStringList SupportedMimeTypes READ empty)

public:
    explicit FakePlayerRoot(QObject *parent) : QDBusAbstractAdaptor(parent) { }
    QString identity() const { return QStringLiteral("Other player"); }
    QString desktopEntry() const { return QStringLiteral("other-player"); }
    bool no() const { return false; }
    QStringList empty() const { return {}; }
};

class FakePlayer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus)
    Q_PROPERTY(double Rate READ one)
    Q_PROPERTY(double MinimumRate READ one)
    Q_PROPERTY(double MaximumRate READ one)
    Q_PROPERTY(double Volume READ one)
    Q_PROPERTY(bool Shuffle READ no)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(bool CanControl READ yes)
    Q_PROPERTY(bool CanGoNext READ yes)
    Q_PROPERTY(bool CanGoPrevious READ no)
    Q_PROPERTY(bool CanPlay READ yes)
    Q_PROPERTY(bool CanPause READ yes)
    Q_PROPERTY(bool CanSeek READ no)

public:
    explicit FakePlayer(QObject *parent) : QDBusAbstractAdaptor(parent) { }
    QString playbackStatus() const { return QStringLiteral("Playing"); }
    QString loopStatus() const { return QStringLiteral("None"); }
    double one() const { return 1.0; }
    bool yes() const { return true; }
    bool no() const { return false; }
    qlonglong position() const { return 0; }
    QVariantMap metadata() const
    {
        return { { QStringLiteral("mpris:trackid"),
                   QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/keel/track/1"))) },
                 { QStringLiteral("xesam:title"), QStringLiteral("Other song") },
                 { QStringLiteral("xesam:artist"), QStringList { QStringLiteral("Other band") } } };
    }
    int nexts = 0;

public Q_SLOTS:
    void Next() { ++nexts; }
    void Previous() { }
    void Pause() { }
    void PlayPause() { }
    void Stop() { }
    void Play() { }
    void Seek(qlonglong) { }
    void SetPosition(const QDBusObjectPath &, qlonglong) { }
    void OpenUri(const QString &) { }
};

} // namespace

class tst_AmberMpris : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void playerOnTheBus();
    void controllerFollowsAnotherPlayer();

private:
    // Waits for an asynchronous call: the players answer from this thread's
    // event loop.
    static QDBusMessage call(const QDBusConnection &bus, const QString &service, const QString &iface,
                             const QString &method, const QVariantList &args);
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_AmberMpris::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

QDBusMessage tst_AmberMpris::call(const QDBusConnection &bus, const QString &service, const QString &iface,
                                  const QString &method, const QVariantList &args)
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/org/mpris/MediaPlayer2"), iface,
                                                    method);
    m.setArguments(args);
    QDBusPendingCall pending = bus.asyncCall(m);
    QElapsedTimer timer;
    timer.start();
    while (!pending.isFinished() && timer.elapsed() < 5000)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return pending.isFinished() ? pending.reply() : QDBusMessage();
}

void tst_AmberMpris::playerOnTheBus()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(
import QtQuick 2.0
import Amber.Mpris 1.0
Item {
    property bool isPlaying: true
    property int nexts
    property int toggles
    property real seekOffset
    MprisPlayer {
        id: mprisPlayer
        serviceName: "keelamber"
        identity: "Keel Amber player"
        desktopEntry: "keel-amber"
        canControl: true
        canGoNext: true
        canPlay: true
        canPause: true
        canSeek: true
        playbackStatus: isPlaying ? Mpris.Playing : Mpris.Paused
        metaData.title: "Song"
        metaData.contributingArtist: ["Band"]
        metaData.albumTitle: "Album"
        metaData.duration: 180000
        onNextRequested: nexts++
        onPlayPauseRequested: { toggles++; isPlaying = !isPlaying }
        onSeekRequested: function(offset) { seekOffset = offset }
    }
})QML",
              QUrl(QStringLiteral("player.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));

    // Amber's QML MprisPlayer adds the process to the name, so that two
    // instances of an app are two players.
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.keelamber.instance%1")
                                .arg(QCoreApplication::applicationPid());
    QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("client"));
    QTRY_VERIFY(bus.interface()->isServiceRegistered(service).value());

    auto get = [&](const QString &iface, const QString &name) {
        const QDBusMessage r = call(bus, service, QStringLiteral("org.freedesktop.DBus.Properties"),
                                    QStringLiteral("Get"), { iface, name });
        return r.type() == QDBusMessage::ReplyMessage
            ? qvariant_cast<QDBusVariant>(r.arguments().value(0)).variant()
            : QVariant();
    };
    const QString root = QStringLiteral("org.mpris.MediaPlayer2");
    const QString player = QStringLiteral("org.mpris.MediaPlayer2.Player");
    QCOMPARE(get(root, QStringLiteral("Identity")).toString(), QStringLiteral("Keel Amber player"));
    QCOMPARE(get(root, QStringLiteral("DesktopEntry")).toString(), QStringLiteral("keel-amber"));
    QCOMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Playing"));
    QVERIFY(get(player, QStringLiteral("CanGoNext")).toBool());
    QVERIFY(!get(player, QStringLiteral("CanGoPrevious")).toBool());
    const auto metadata = qdbus_cast<QVariantMap>(get(player, QStringLiteral("Metadata")));
    QCOMPARE(metadata.value(QStringLiteral("xesam:title")).toString(), QStringLiteral("Song"));
    QCOMPARE(metadata.value(QStringLiteral("xesam:album")).toString(), QStringLiteral("Album"));
    QCOMPARE(metadata.value(QStringLiteral("xesam:artist")).toStringList(), QStringList { QStringLiteral("Band") });
    // MPRIS lengths are microseconds; Amber's duration is milliseconds.
    QCOMPARE(metadata.value(QStringLiteral("mpris:length")).toLongLong(), 180000000LL);

    // GetAll, as Lipstick's controls read a player.
    const QDBusMessage all = call(bus, service, QStringLiteral("org.freedesktop.DBus.Properties"),
                                  QStringLiteral("GetAll"), { player });
    QCOMPARE(all.type(), QDBusMessage::ReplyMessage);
    QVERIFY(qdbus_cast<QVariantMap>(all.arguments().value(0)).contains(QStringLiteral("CanPause")));

    call(bus, service, player, QStringLiteral("Next"), {});
    QTRY_COMPARE(o->property("nexts").toInt(), 1);
    call(bus, service, player, QStringLiteral("PlayPause"), {});
    QTRY_COMPARE(o->property("toggles").toInt(), 1);
    QTRY_COMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Paused"));
    call(bus, service, player, QStringLiteral("PlayPause"), {});
    QTRY_COMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Playing"));
    call(bus, service, player, QStringLiteral("Seek"), { QVariant::fromValue(static_cast<qlonglong>(5000000)) });
    // Offsets are microseconds on the bus, milliseconds in QML.
    QTRY_COMPARE(o->property("seekOffset").toReal(), 5000.0);
    // Previous is not allowed: an error, no handler.
    const QDBusMessage previous = call(bus, service, player, QStringLiteral("Previous"), {});
    QCOMPARE(previous.type(), QDBusMessage::ErrorMessage);
}

void tst_AmberMpris::controllerFollowsAnotherPlayer()
{
    QDBusConnection other = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("other"));
    QObject playerObject;
    // Owned by playerObject (Qt parent), as D-Bus adaptors are.
    new FakePlayerRoot(&playerObject);
    new FakePlayer(&playerObject);
    auto *fake = playerObject.findChild<FakePlayer *>();
    QVERIFY(other.registerObject(QStringLiteral("/org/mpris/MediaPlayer2"), &playerObject));
    QVERIFY(other.registerService(QStringLiteral("org.mpris.MediaPlayer2.otherplayer")));

    QQmlComponent c(m_engine.get());
    c.setData(R"QML(
import QtQuick 2.0
import Amber.Mpris 1.0
MprisController {
    property string title: metaData.title !== undefined ? metaData.title : ""
})QML",
              QUrl(QStringLiteral("controller.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QTRY_VERIFY(o->property("availableServices").toStringList().contains(
        QStringLiteral("org.mpris.MediaPlayer2.otherplayer")));
    o->setProperty("currentService", QStringLiteral("org.mpris.MediaPlayer2.otherplayer"));
    QTRY_COMPARE(o->property("identity").toString(), QStringLiteral("Other player"));
    QTRY_COMPARE(o->property("title").toString(), QStringLiteral("Other song"));
    QTRY_VERIFY(o->property("canGoNext").toBool());
    QTRY_COMPARE(o->property("playbackStatus").toInt(), 1); // Mpris.Playing

    bool ok = false;
    QVERIFY(QMetaObject::invokeMethod(o.get(), "next", Q_RETURN_ARG(bool, ok)));
    QVERIFY(ok);
    QTRY_COMPARE(fake->nexts, 1);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    tst_AmberMpris test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_ambermpris.moc"
