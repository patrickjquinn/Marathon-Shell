#include <QTest>
#include <QSignalSpy>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QProcess>
#include <QTemporaryDir>

#include "audiodclient.h"
#include "audiomanagercpp.h"
#include "audioroutingmanager.h"
#include "sinkvolume.h"

class FakeAudio : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Audio1")
    Q_PROPERTY(QString DefaultSink MEMBER defaultSink)
    Q_PROPERTY(double Volume MEMBER volume)
    Q_PROPERTY(bool Muted MEMBER muted)
    Q_PROPERTY(QList<AudiodStream> Streams MEMBER streams)

  public:
    QString             defaultSink = QStringLiteral("alsa_output.speaker");
    double              volume      = 0.4;
    bool                muted       = false;
    QList<AudiodStream> streams;
    QVariantList        calls;

  public slots:
    void SetVolume(double v) {
        calls.append(QVariant(QVariantList{"SetVolume", v}));
    }
    void SetMuted(bool m) {
        calls.append(QVariant(QVariantList{"SetMuted", m}));
    }
    void SetStreamVolume(uint id, double v) {
        calls.append(QVariant(QVariantList{"SetStreamVolume", id, v}));
    }
    void SetInputMuted(bool m) {
        calls.append(QVariant(QVariantList{"SetInputMuted", m}));
    }
    void SetSpeakerphone(bool on) {
        calls.append(QVariant(QVariantList{"SetSpeakerphone", on}));
    }
};

class TestAudiodClient : public QObject {
    Q_OBJECT

    QTemporaryDir dir;

    struct Bus {
        QProcess daemon;
        QString  address;
        ~Bus() {
            daemon.kill();
            daemon.waitForFinished();
        }
    };

    bool startBus(Bus &bus) {
        const QString config = dir.filePath("bus.conf");
        QFile         c(config);
        if (!c.open(QIODevice::WriteOnly))
            return false;
        c.write(QStringLiteral("<busconfig><type>session</type><listen>unix:tmpdir=%1</listen>"
                               "<policy context=\"default\"><allow send_destination=\"*\"/>"
                               "<allow eavesdrop=\"true\"/><allow own=\"*\"/></policy>"
                               "</busconfig>")
                    .arg(dir.path())
                    .toUtf8());
        c.close();
        bus.daemon.start("dbus-daemon", {"--config-file=" + config, "--nofork", "--print-address"});
        if (!bus.daemon.waitForReadyRead(5000))
            return false;
        bus.address = QString::fromUtf8(bus.daemon.readLine()).trimmed();
        return !bus.address.isEmpty();
    }

    bool serve(QDBusConnection &conn, FakeAudio &fake) {
        return conn.registerObject("/org/marathonos/Audio", &fake,
                                   QDBusConnection::ExportAllSlots |
                                       QDBusConnection::ExportAllProperties) &&
            conn.registerService(AudiodClient::serviceName());
    }

    static void changeProperties(QDBusConnection &service, const QVariantMap &changed) {
        QDBusMessage msg = QDBusMessage::createSignal(
            "/org/marathonos/Audio", "org.freedesktop.DBus.Properties", "PropertiesChanged");
        msg << QString("org.marathonos.Audio1") << changed << QStringList();
        QVERIFY(service.send(msg));
    }

  private slots:
    void initTestCase() {
        qDBusRegisterMetaType<AudiodStream>();
        qDBusRegisterMetaType<QList<AudiodStream>>();
    }

    // The shell's volume is the service's default sink, read at start.
    void readsTheDefaultSink() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeAudio fake;
        fake.streams            = {{7, QStringLiteral("Music"), 0.5, true}};
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "a2");
        QVERIFY(serve(service, fake));
        AudiodClient client(QDBusConnection::connectToBus(bus.address, "a1"));
        SinkVolume   volume(&client);
        client.refresh();
        QTRY_VERIFY(client.available());
        QCOMPARE(volume.sink(), QString("alsa_output.speaker"));
        QCOMPARE(volume.volume(), 0.4);
        QCOMPARE(client.streams().size(), 1);
        QCOMPARE(client.streams()[0].id, 7u);
        QCOMPARE(client.streams()[0].name, QString("Music"));
        QVERIFY(client.streams()[0].muted);
    }

    // A Bluetooth speaker becomes the default; its level follows.
    void followsPropertiesChanged() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeAudio       fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "b2");
        QVERIFY(serve(service, fake));
        AudiodClient client(QDBusConnection::connectToBus(bus.address, "b1"));
        SinkVolume   volume(&client);
        client.refresh();
        QTRY_VERIFY(client.available());

        QSignalSpy streams(&client, &AudiodClient::streamsChanged);
        changeProperties(service,
                         {{"DefaultSink", "bluez_output.AA"},
                          {"Volume", 0.8},
                          {"Muted", true},
                          {"Streams",
                           QVariant::fromValue(
                               QList<AudiodStream>{{3, QStringLiteral("Podcast"), 1.0, false}})}});
        QTRY_COMPARE(volume.sink(), QString("bluez_output.AA"));
        QCOMPARE(volume.volume(), 0.8);
        QVERIFY(volume.muted());
        QTRY_COMPARE(streams.count(), 1);
        QCOMPARE(client.streams()[0].name, QString("Podcast"));
    }

    void writesReachTheService() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeAudio       fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "c2");
        QVERIFY(serve(service, fake));
        AudiodClient client(QDBusConnection::connectToBus(bus.address, "c1"));
        SinkVolume   volume(&client);
        client.refresh();
        QTRY_VERIFY(client.available());

        QSignalSpy written(&client, &SinkBackend::volumeWritten);
        volume.setVolume(0.25);
        QTRY_COMPARE(written.count(), 1);
        client.setStreamVolume(3, 0.5);
        client.setInputMuted(true);
        client.setSpeakerphone(true);
        QTRY_COMPARE(fake.calls.size(), 4);
        QCOMPARE(fake.calls[0].toList(), (QVariantList{"SetVolume", 0.25}));
        QCOMPARE(fake.calls[1].toList(), (QVariantList{"SetStreamVolume", 3u, 0.5}));
        QCOMPARE(fake.calls[2].toList(), (QVariantList{"SetInputMuted", true}));
        QCOMPARE(fake.calls[3].toList(), (QVariantList{"SetSpeakerphone", true}));
    }

    // While the service is gone nothing is written; when it is back, a
    // level set meanwhile reaches it.
    void serviceComingBackIsReadAgain() {
        Bus bus;
        QVERIFY(startBus(bus));
        AudiodClient client(QDBusConnection::connectToBus(bus.address, "d1"));
        SinkVolume   volume(&client);
        client.refresh();
        QTest::qWait(200);
        QVERIFY(!client.available());
        volume.setVolume(0.6);

        FakeAudio       fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "d2");
        QVERIFY(serve(service, fake));
        QTRY_VERIFY(client.available());
        QTRY_COMPARE(fake.calls.size(), 1);
        QCOMPARE(fake.calls[0].toList(), (QVariantList{"SetVolume", 0.6}));

        service.unregisterService(AudiodClient::serviceName());
        QTRY_VERIFY(!client.available());
        QVERIFY(volume.sink().isEmpty());
    }

    // Speakerphone and call mute go to the service (WirePlumber's call
    // policy reads the first); a call's end leaves the next on the earpiece
    // with the microphone open. Last: it claims the process's session bus.
    void callControlsReachTheService() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeAudio       fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "e2");
        QVERIFY(serve(service, fake));
        qputenv("DBUS_SESSION_BUS_ADDRESS", bus.address.toUtf8());
        AudioManagerCpp     audio;
        AudioRoutingManager routing(&audio);
        QTRY_VERIFY(audio.available());

        routing.startCallAudio();
        routing.setSpeakerphone(true);
        routing.setMuted(true);
        routing.stopCallAudio();
        QTRY_COMPARE(fake.calls.size(), 4);
        QCOMPARE(fake.calls[0].toList(), (QVariantList{"SetSpeakerphone", true}));
        QCOMPARE(fake.calls[1].toList(), (QVariantList{"SetInputMuted", true}));
        QCOMPARE(fake.calls[2].toList(), (QVariantList{"SetInputMuted", false}));
        QCOMPARE(fake.calls[3].toList(), (QVariantList{"SetSpeakerphone", false}));
        QVERIFY(!routing.isInCall());
        QVERIFY(!routing.isSpeakerphoneEnabled());
        QVERIFY(!routing.isMuted());
    }
};

QTEST_GUILESS_MAIN(TestAudiodClient)
#include "test_audiodclient.moc"
