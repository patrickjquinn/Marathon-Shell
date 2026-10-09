// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// org.nemomobile.mpris (qtmpris for Qt 6) on a private session bus, used as
// hutspot uses it: an MprisPlayer publishes org.mpris.MediaPlayer2.<name>
// with its status and metadata, which a plain D-Bus MPRIS client (as
// Lipstick's media controls are) reads; the client's Next and PlayPause
// reach the QML handlers.

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QElapsedTimer>
#include <QDBusVariant>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTest>
#include <memory>

class tst_Mpris : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void playerOnTheBus();

private:
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Mpris::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_Mpris::playerOnTheBus()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(
import QtQuick 2.0
import org.nemomobile.mpris 1.0
Item {
    property bool isPlaying: true
    property int nexts
    property int toggles
    MprisPlayer {
        id: mprisPlayer
        serviceName: "keeltest"
        identity: "Keel test player"
        canControl: true
        canGoNext: true
        canPlay: true
        canPause: true
        playbackStatus: isPlaying ? Mpris.Playing : Mpris.Paused
        onNextRequested: nexts++
        // qtmpris answers PlayPause with pauseRequested or playRequested,
        // from the current playbackStatus.
        onPauseRequested: { toggles++; isPlaying = false }
        onPlayRequested: { toggles++; isPlaying = true }
        Component.onCompleted: {
            var metadata = {}
            metadata[Mpris.metadataToString(Mpris.Title)] = "Song"
            metadata[Mpris.metadataToString(Mpris.Artist)] = ["Band"]
            mprisPlayer.metadata = metadata
        }
    }
})QML",
              QUrl(QStringLiteral("player.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));

    const QString service = QStringLiteral("org.mpris.MediaPlayer2.keeltest");
    QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("client"));
    QTRY_VERIFY(bus.interface()->isServiceRegistered(service).value());

    // Asynchronous calls: the player answers from this thread's event loop.
    // Plain messages (a QDBusInterface would introspect the player with a
    // blocking call, which this thread cannot answer).
    auto call = [&](const QString &iface, const QString &method, const QVariantList &args) {
        QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/org/mpris/MediaPlayer2"),
                                                        iface, method);
        m.setArguments(args);
        QDBusPendingCall pending = bus.asyncCall(m);
        QElapsedTimer timer;
        timer.start();
        while (!pending.isFinished() && timer.elapsed() < 5000)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        return pending.isFinished() ? pending.reply() : QDBusMessage();
    };
    auto get = [&](const QString &iface, const QString &name) {
        const QDBusMessage r = call(QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"),
                                    { iface, name });
        return r.type() == QDBusMessage::ReplyMessage
            ? qvariant_cast<QDBusVariant>(r.arguments().value(0)).variant()
            : QVariant();
    };
    const QString player = QStringLiteral("org.mpris.MediaPlayer2.Player");
    QCOMPARE(get(QStringLiteral("org.mpris.MediaPlayer2"), QStringLiteral("Identity")).toString(),
             QStringLiteral("Keel test player"));
    QCOMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Playing"));
    QVERIFY(get(player, QStringLiteral("CanGoNext")).toBool());
    const auto metadata = qdbus_cast<QVariantMap>(get(player, QStringLiteral("Metadata")));
    QCOMPARE(metadata.value(QStringLiteral("xesam:title")).toString(), QStringLiteral("Song"));

    call(player, QStringLiteral("Next"), {});
    QTRY_COMPARE(o->property("nexts").toInt(), 1);
    call(player, QStringLiteral("PlayPause"), {});
    QTRY_COMPARE(o->property("toggles").toInt(), 1);
    QTRY_COMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Paused"));
    call(player, QStringLiteral("PlayPause"), {});
    QTRY_COMPARE(o->property("toggles").toInt(), 2);
    QTRY_COMPARE(get(player, QStringLiteral("PlaybackStatus")).toString(), QStringLiteral("Playing"));
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    tst_Mpris test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_mpris.moc"
