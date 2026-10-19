#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QSignalSpy>
#include <QTest>
#include <QThread>

#include "bluetoothmanager.h"

namespace {
    constexpr auto kAdapter = "/org/bluez/hci0";
    constexpr auto kDevice  = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF";
}

class ObjectManagerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.DBus.ObjectManager")
  public:
    explicit ObjectManagerAdaptor(QObject *parent)
        : QDBusAbstractAdaptor(parent) {}
  public slots:
    ManagedObjectMap GetManagedObjects() {
        return {{QDBusObjectPath(kAdapter), {{"org.bluez.Adapter1", {}}}},
                {QDBusObjectPath(kDevice), {{"org.bluez.Device1", {}}}}};
    }
};

class AdapterAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Adapter1")
    Q_PROPERTY(bool Powered MEMBER powered)
    Q_PROPERTY(QString Alias MEMBER alias)
  public:
    explicit AdapterAdaptor(QObject *parent)
        : QDBusAbstractAdaptor(parent) {}
    bool    powered = true;
    QString alias   = QStringLiteral("hackberrypi");
};

class DeviceAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Device1")
    Q_PROPERTY(QString Address MEMBER address)
    Q_PROPERTY(QString Name MEMBER name)
    Q_PROPERTY(QString Alias MEMBER name)
    Q_PROPERTY(bool Paired MEMBER paired)
    Q_PROPERTY(bool Connected MEMBER connected)
    Q_PROPERTY(QString Icon MEMBER icon)
  public:
    explicit DeviceAdaptor(QObject *parent)
        : QDBusAbstractAdaptor(parent) {}
    QString address   = QStringLiteral("AA:BB:CC:DD:EE:FF");
    QString name      = QStringLiteral("Speaker");
    bool    paired    = true;
    bool    connected = false;
    QString icon      = QStringLiteral("audio-card");
};

// Answers on its own thread: BluetoothManager makes blocking calls.
class BluezThread : public QThread {
  public:
    QList<QObject *> objects;
    QThread         *home = nullptr;
    void             run() override {
        exec();
        for (QObject *o : std::as_const(objects))
            o->moveToThread(home);
    }
};

// bluetoothd as BluetoothManager sees it, on the test's private bus.
class FakeBluez : public QObject {
    Q_OBJECT
  public:
    QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "fake-bluez");
    QObject         root, adapter, device;
    DeviceAdaptor  *deviceProps = new DeviceAdaptor(&device);
    BluezThread     thread;

    ~FakeBluez() override {
        thread.quit();
        thread.wait();
        QDBusConnection::disconnectFromBus("fake-bluez");
    }

    bool publish() {
        new ObjectManagerAdaptor(&root);
        new AdapterAdaptor(&adapter);
        thread.objects = {&root, &adapter, &device};
        thread.home    = QThread::currentThread();
        for (QObject *o : std::as_const(thread.objects))
            o->moveToThread(&thread);
        thread.start();
        return bus.registerObject("/", &root, QDBusConnection::ExportAdaptors) &&
            bus.registerObject(kAdapter, &adapter, QDBusConnection::ExportAdaptors) &&
            bus.registerObject(kDevice, &device, QDBusConnection::ExportAdaptors) &&
            bus.registerService("org.bluez");
    }

    // A device discovery finds: BlueZ announces it with its properties.
    void deviceFound(const QString &path, const QVariantMap &props) const {
        QDBusMessage s = QDBusMessage::createSignal("/", "org.freedesktop.DBus.ObjectManager",
                                                    "InterfacesAdded");
        s << QVariant::fromValue(QDBusObjectPath(path))
          << QVariant::fromValue(InterfaceMap{{"org.bluez.Device1", props}});
        bus.send(s);
    }

    void deviceChanged(const QVariantMap &changed) const {
        QDBusMessage s = QDBusMessage::createSignal(kDevice, "org.freedesktop.DBus.Properties",
                                                    "PropertiesChanged");
        s << QStringLiteral("org.bluez.Device1") << changed << QStringList();
        bus.send(s);
    }
};

class TestBluetoothManager : public QObject {
    Q_OBJECT

    static QObject *pairedDevice(const BluetoothManager &bt) {
        const QList<QObject *> paired = bt.pairedDevices();
        return paired.size() == 1 ? paired.first() : nullptr;
    }

  private slots:
    void initTestCase() {
        // BluetoothManager talks to the system bus; point it at this test's bus.
        qputenv("DBUS_SYSTEM_BUS_ADDRESS", qgetenv("DBUS_SESSION_BUS_ADDRESS"));
        qDBusRegisterMetaType<PropertyMap>();
        qDBusRegisterMetaType<InterfaceMap>();
        qDBusRegisterMetaType<ManagedObjectMap>();
    }

    // The HackberryPi's speaker module connects after the shell has listed it.
    void followsADeviceConnectingLater() {
        FakeBluez bluez;
        QVERIFY(bluez.publish());
        BluetoothManager bt;
        QTRY_VERIFY(pairedDevice(bt));
        QVERIFY(!pairedDevice(bt)->property("connected").toBool());

        QSignalSpy pairedChanged(&bt, &BluetoothManager::pairedDevicesChanged);
        bluez.deviceProps->connected = true;
        bluez.deviceChanged({{"Connected", true}});
        QTRY_VERIFY(!pairedChanged.isEmpty());
        QVERIFY(pairedDevice(bt)->property("connected").toBool());
        QCOMPARE(pairedDevice(bt)->property("name").toString(), QStringLiteral("Speaker"));
    }

    void listsADeviceOncePaired() {
        FakeBluez bluez;
        bluez.deviceProps->paired = false;
        QVERIFY(bluez.publish());
        BluetoothManager bt;
        QTRY_COMPARE(bt.devices().size(), 1);
        QVERIFY(bt.pairedDevices().isEmpty());

        QSignalSpy pairedChanged(&bt, &BluetoothManager::pairedDevicesChanged);
        bluez.deviceProps->paired = true;
        bluez.deviceChanged({{"Paired", true}});
        QTRY_VERIFY(!pairedChanged.isEmpty());
        QVERIFY(pairedDevice(bt));
    }

    // Listed from the announcement alone; nothing polls BlueZ for it.
    void listsADeviceFoundByDiscovery() {
        FakeBluez bluez;
        QVERIFY(bluez.publish());
        BluetoothManager bt;
        QTRY_COMPARE(bt.devices().size(), 1);
        bluez.deviceFound(QStringLiteral("/org/bluez/hci0/dev_11_22_33_44_55_66"),
                          {{"Address", QStringLiteral("11:22:33:44:55:66")},
                           {"Name", QStringLiteral("Headphones")},
                           {"Paired", false}});
        QTRY_COMPARE(bt.devices().size(), 2);
        QCOMPARE(bt.devices().last()->property("name").toString(), QStringLiteral("Headphones"));
    }
};

QTEST_GUILESS_MAIN(TestBluetoothManager)
#include "test_bluetoothmanager.moc"
