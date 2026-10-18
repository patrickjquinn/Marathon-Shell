// clazy:excludeall=qproperty-without-notify (D-Bus properties; QtDBus has no NOTIFY)

#include <QTest>
#include <QSignalSpy>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QProcess>
#include <QTemporaryDir>

#include "weatherclient.h"

class FakeWeather : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Weather1")
    Q_PROPERTY(QString Forecast READ forecast)
    Q_PROPERTY(QString State READ state)

  public:
    QString      forecastJson;
    QString      stateText = QStringLiteral("idle");
    int          refreshes = 0;
    QVariantList located;
    int          automatic = 0;

    QString      forecast() const {
        return forecastJson;
    }
    QString state() const {
        return stateText;
    }

  public slots:
    void Refresh() {
        ++refreshes;
    }
    void SetLocation(const QString &name, const QString &region, double latitude,
                     double longitude) {
        located = {name, region, latitude, longitude};
    }
    void SetAutomatic() {
        ++automatic;
    }
    QString Search(const QString &query) {
        return QStringLiteral(R"([{"name":"%1","region":"Pirkanmaa, Finland",)"
                              R"("latitude":61.4981,"longitude":23.7608}])")
            .arg(query);
    }
};

class TestWeatherClient : public QObject {
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

    bool serve(QDBusConnection &conn, FakeWeather &fake) {
        return conn.registerObject("/org/marathonos/Weather", &fake,
                                   QDBusConnection::ExportAllSlots |
                                       QDBusConnection::ExportAllProperties) &&
            conn.registerService(WeatherClient::serviceName());
    }

  private slots:
    void refreshReadsThenAsks() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeWeather fake;
        fake.forecastJson = R"({"location":{"name":"Tampere"},"current":{"temperature":2.1}})";
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "a2");
        QVERIFY(serve(service, fake));
        WeatherClient client(QDBusConnection::connectToBus(bus.address, "a1"));
        QVERIFY(client.forecast().isEmpty());
        client.refresh();
        QTRY_COMPARE(fake.refreshes, 1);
        QCOMPARE(client.forecast().value("location").toMap().value("name").toString(), QString("Tampere"));
        QCOMPARE(client.forecast().value("current").toMap().value("temperature").toDouble(), 2.1);
        QCOMPARE(client.state(), QString("idle"));
    }

    void followsPropertiesChanged() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeWeather     fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "b2");
        QVERIFY(serve(service, fake));
        WeatherClient client(QDBusConnection::connectToBus(bus.address, "b1"));
        QSignalSpy    forecastSpy(&client, &WeatherClient::forecastChanged);
        QSignalSpy    stateSpy(&client, &WeatherClient::stateChanged);
        QTest::qWait(100);

        QDBusMessage changed = QDBusMessage::createSignal(
            "/org/marathonos/Weather", "org.freedesktop.DBus.Properties", "PropertiesChanged");
        changed << QString("org.marathonos.Weather1")
                << QVariantMap{{"State", "updating"},
                               {"Forecast", R"({"location":{"name":"Dublin"}})"}}
                << QStringList();
        QVERIFY(service.send(changed));
        QTRY_COMPARE(stateSpy.count(), 1);
        QCOMPARE(client.state(), QString("updating"));
        QCOMPARE(forecastSpy.count(), 1);
        QCOMPARE(client.forecast().value("location").toMap().value("name").toString(), QString("Dublin"));

        // The same JSON again is not a change.
        QVERIFY(service.send(changed));
        QTest::qWait(100);
        QCOMPARE(forecastSpy.count(), 1);
    }

    void searchAnswersWithPlaces() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeWeather     fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "c2");
        QVERIFY(serve(service, fake));
        WeatherClient client(QDBusConnection::connectToBus(bus.address, "c1"));
        QSignalSpy    spy(&client, &WeatherClient::searchFinished);
        client.search("Tampere");
        QTRY_COMPARE(spy.count(), 1);
        const QVariantList places = spy.at(0).at(0).toList();
        QCOMPARE(places.size(), 1);
        QCOMPARE(places[0].toMap().value("name").toString(), QString("Tampere"));
        QVERIFY(spy.at(0).at(1).toString().isEmpty());
    }

    void searchWithoutTheServiceReportsAnError() {
        Bus bus;
        QVERIFY(startBus(bus));
        WeatherClient client(QDBusConnection::connectToBus(bus.address, "d1"));
        QSignalSpy    spy(&client, &WeatherClient::searchFinished);
        client.search("Tampere");
        QTRY_COMPARE(spy.count(), 1);
        QVERIFY(spy.at(0).at(0).toList().isEmpty());
        QVERIFY(!spy.at(0).at(1).toString().isEmpty());
    }

    void choosesALocation() {
        Bus bus;
        QVERIFY(startBus(bus));
        FakeWeather     fake;
        QDBusConnection service = QDBusConnection::connectToBus(bus.address, "e2");
        QVERIFY(serve(service, fake));
        WeatherClient client(QDBusConnection::connectToBus(bus.address, "e1"));
        client.setLocation({{"name", "Tampere"},
                            {"region", "Pirkanmaa, Finland"},
                            {"latitude", 61.4981},
                            {"longitude", 23.7608}});
        QTRY_COMPARE(fake.located.size(), 4);
        QCOMPARE(fake.located[0].toString(), QString("Tampere"));
        QCOMPARE(fake.located[2].toDouble(), 61.4981);
        client.setAutomatic();
        QTRY_COMPARE(fake.automatic, 1);
    }
};

QTEST_MAIN(TestWeatherClient)
#include "test_weatherclient.moc"
