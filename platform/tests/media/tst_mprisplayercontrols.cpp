// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media's MprisPlayerControls on a private session bus, used as
// Jolla's lock screen uses it (LockItem.qml): a Loader whose item follows a
// fake MPRIS player another connection publishes (title, artist,
// isPlaying, enabled while a player is on the bus) and whose buttons emit
// the *Requested signals and reach the player.

#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTest>

#include <memory>

namespace {

const QString PlayerPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString PlayerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");

class FakeRoot : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(bool CanQuit READ no)
    Q_PROPERTY(bool CanRaise READ no)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString DesktopEntry READ identity)
    Q_PROPERTY(QStringList SupportedUriSchemes READ none)
    Q_PROPERTY(QStringList SupportedMimeTypes READ none)

public:
    explicit FakeRoot(QObject *parent) : QDBusAbstractAdaptor(parent) { }
    QString identity() const { return QStringLiteral("fakeplayer"); }
    bool no() const { return false; }
    QStringList none() const { return {}; }
};

// A player that can go back and forth and play or pause.
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
    Q_PROPERTY(bool CanGoPrevious READ yes)
    Q_PROPERTY(bool CanPlay READ yes)
    Q_PROPERTY(bool CanPause READ yes)
    Q_PROPERTY(bool CanSeek READ no)

public:
    FakePlayer(QObject *parent, QDBusConnection bus)
        : QDBusAbstractAdaptor(parent)
        , m_bus(std::move(bus))
    {
    }
    QString playbackStatus() const { return m_playing ? QStringLiteral("Playing") : QStringLiteral("Paused"); }
    static QString loopStatus() { return QStringLiteral("None"); }
    static double one() { return 1.0; }
    static bool yes() { return true; }
    static bool no() { return false; }
    static qlonglong position() { return 0; }
    QVariantMap metadata() const
    {
        return { { QStringLiteral("mpris:trackid"),
                   QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/keel/track/%1").arg(m_track))) },
                 { QStringLiteral("xesam:title"), QStringLiteral("Song %1").arg(m_track) },
                 { QStringLiteral("xesam:artist"),
                   QStringList { QStringLiteral("Band"), QStringLiteral("Guest") } } };
    }

    int playPauses = 0;
    int nexts = 0;
    int previouses = 0;

public Q_SLOTS:
    void Next()
    {
        ++nexts;
        ++m_track;
        changed(QStringLiteral("Metadata"), metadata());
    }
    void Previous() { ++previouses; }
    void PlayPause()
    {
        ++playPauses;
        m_playing = !m_playing;
        changed(QStringLiteral("PlaybackStatus"), playbackStatus());
    }
    void Pause() { }
    void Play() { }
    void Stop() { }
    void Seek(qlonglong) { }
    void SetPosition(const QDBusObjectPath &, qlonglong) { }
    void OpenUri(const QString &) { }

private:
    void changed(const QString &name, const QVariant &value)
    {
        QDBusMessage signal = QDBusMessage::createSignal(PlayerPath, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                         QStringLiteral("PropertiesChanged"));
        signal << PlayerInterface << QVariantMap { { name, value } } << QStringList();
        m_bus.send(signal);
    }

    QDBusConnection m_bus;
    bool m_playing = true;
    int m_track = 1;
};

} // namespace

class TestMprisPlayerControls : public QObject
{
    Q_OBJECT

private slots:
    void lockScreenUse();

private:
    static QQuickItem *child(QQuickItem *item, const char *name)
    {
        return item->findChild<QQuickItem *>(QLatin1String(name));
    }
};

void TestMprisPlayerControls::lockScreenUse()
{
    QQuickView view;
    view.engine()->addImportPath(QStringLiteral(KEEL_QML_DIR));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(540, 400);
    view.setSource(QUrl::fromLocalFile(QStringLiteral(QUICK_TEST_SOURCE_DIR "/LockScreenMpris.qml")));
    QVERIFY2(view.status() == QQuickView::Ready, qPrintable(view.errors().isEmpty() ? QString()
                                                                                      : view.errors().first().toString()));
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QQuickItem *rootItem = view.rootObject();

    // The item is there (Amber.Mpris is installed) and set up as the lock
    // screen does; no player yet: not enabled.
    QTRY_VERIFY(rootItem->property("item").value<QQuickItem *>());
    auto *item = rootItem->property("item").value<QQuickItem *>();
    QCOMPARE(item->width(), 540.0);
    QVERIFY(!item->isEnabled());
    QVERIFY(!rootItem->property("shown").toBool());

    QDBusConnection other = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("player"));
    QObject playerObject;
    // Children of playerObject, as D-Bus adaptors must be; destroyed first.
    FakeRoot root(&playerObject);
    FakePlayer fakePlayer(&playerObject, other);
    FakePlayer *player = &fakePlayer;
    QVERIFY(other.registerObject(PlayerPath, &playerObject));
    QVERIFY(other.registerService(QStringLiteral("org.mpris.MediaPlayer2.fakeplayer")));

    QTRY_VERIFY(item->isEnabled());
    QTRY_VERIFY(rootItem->property("shown").toBool());
    QTRY_COMPARE(child(item, "titleLabel")->property("text").toString(), QStringLiteral("Song 1"));
    QCOMPARE(child(item, "artistLabel")->property("text").toString(), QStringLiteral("Band, Guest"));
    QTRY_VERIFY(item->property("isPlaying").toBool());
    QVERIFY(item->height() > 0);

    auto click = [&](const char *name) {
        QQuickItem *button = child(item, name);
        QVERIFY(button);
        QTRY_VERIFY(button->isEnabled());
        QTest::mouseClick(&view, Qt::LeftButton, {},
                          button->mapToScene(QPointF(button->width() / 2, button->height() / 2)).toPoint());
    };

    click("playPauseButton");
    QTRY_COMPARE(player->playPauses, 1);
    QCOMPARE(rootItem->property("playPauseRequests").toInt(), 1);
    QTRY_VERIFY(!item->property("isPlaying").toBool());

    click("nextButton");
    QTRY_COMPARE(player->nexts, 1);
    QCOMPARE(rootItem->property("nextRequests").toInt(), 1);
    QTRY_COMPARE(child(item, "titleLabel")->property("text").toString(), QStringLiteral("Song 2"));

    click("previousButton");
    QTRY_COMPARE(player->previouses, 1);
    QCOMPARE(rootItem->property("previousRequests").toInt(), 1);

    // The lock screen hides the controls after a while without playback.
    item->setProperty("enabled", false);
    QVERIFY(!rootItem->property("shown").toBool());

    // The player leaves the bus.
    QVERIFY(other.unregisterService(QStringLiteral("org.mpris.MediaPlayer2.fakeplayer")));
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    TestMprisPlayerControls test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_mprisplayercontrols.moc"
