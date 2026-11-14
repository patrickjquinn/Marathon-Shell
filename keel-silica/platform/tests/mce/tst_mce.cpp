// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Nemo.Mce (libmce-qt for Qt 6) against a fake MCE (com.nokia.mce) on a
// private bus standing in for the system bus: the QML types read the
// current state with MCE's get_* requests once MCE is on the bus, follow its
// *_ind signals, and become invalid when MCE goes away.

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTest>
#include <memory>

namespace {

const QString McePath = QStringLiteral("/com/nokia/mce/request");
const QString SignalPath = QStringLiteral("/com/nokia/mce/signal");
const QString SignalInterface = QStringLiteral("com.nokia.mce.signal");

class FakeMce : public QDBusVirtualObject
{
public:
    FakeMce()
        : m_bus(QDBusConnection::connectToBus(QDBusConnection::SystemBus, QStringLiteral("mce")))
    {
    }
    ~FakeMce() override { stop(); }

    bool start()
    {
        return m_bus.registerVirtualObject(McePath, this) && m_bus.registerService(QStringLiteral("com.nokia.mce"));
    }
    void stop()
    {
        m_bus.unregisterService(QStringLiteral("com.nokia.mce"));
        m_bus.unregisterObject(McePath);
    }

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &) override
    {
        if (message.interface() != QLatin1String("com.nokia.mce.request"))
            return false;
        requests.append(message.member());
        const auto it = replies.constFind(message.member());
        if (it == replies.constEnd()) {
            m_bus.send(message.createErrorReply(QDBusError::UnknownMethod, message.member()));
        } else {
            m_bus.send(message.createReply(it.value()));
        }
        return true;
    }

    void emitSignal(const QString &name, const QVariantList &args)
    {
        QDBusMessage signal = QDBusMessage::createSignal(SignalPath, SignalInterface, name);
        signal.setArguments(args);
        m_bus.send(signal);
    }

    QHash<QString, QVariantList> replies {
        { QStringLiteral("get_display_status"), { QStringLiteral("on") } },
        { QStringLiteral("get_tklock_mode"), { QStringLiteral("unlocked") } },
        { QStringLiteral("get_battery_level"), { 57 } },
        { QStringLiteral("get_battery_status"), { QStringLiteral("ok") } },
        { QStringLiteral("get_battery_state"), { QStringLiteral("discharging") } },
        { QStringLiteral("get_usb_cable_state"), { QStringLiteral("disconnected") } },
        { QStringLiteral("get_charger_state"), { QStringLiteral("off") } },
        { QStringLiteral("get_charger_type"), { QStringLiteral("none") } },
        { QStringLiteral("get_charging_state"), { QStringLiteral("enabled") } },
        { QStringLiteral("get_psm_state"), { false } },
        { QStringLiteral("get_call_state"), { QStringLiteral("none"), QStringLiteral("normal") } },
    };
    QStringList requests;

private:
    QDBusConnection m_bus;
};

} // namespace

class tst_Mce : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void followsMce();

private:
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Mce::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SYSTEM_BUS_ADDRESS"))
        QSKIP("needs a private bus (dbus-run-session)");
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_Mce::followsMce()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(import QtQuick 2.0
import Nemo.Mce 1.0
QtObject {
    property MceDisplay display: MceDisplay {}
    property MceTkLock tklock: MceTkLock {}
    property MceBatteryLevel batteryLevel: MceBatteryLevel {}
    property MceBatteryStatus batteryStatus: MceBatteryStatus {}
    property MceBatteryState batteryState: MceBatteryState {}
    property MceCableState cable: MceCableState {}
    property MceChargerState charger: MceChargerState {}
    property MceChargerType chargerType: MceChargerType {}
    property MceChargingState charging: MceChargingState {}
    property McePowerSaveMode powerSave: McePowerSaveMode {}
    property MceCallState call: MceCallState {}
    property MceNameOwner owner: MceNameOwner {}
    readonly property bool displayOn: display.valid && display.state === MceDisplay.DisplayOn
    readonly property bool locked: tklock.valid && tklock.locked
    readonly property int percent: batteryLevel.valid ? batteryLevel.percent : -1
    readonly property bool ringing: call.valid && call.state === MceCallState.Ringing
    readonly property bool emergency: call.type === MceCallState.Emergency
    readonly property bool batteryCharging: batteryState.valid && batteryState.value === MceBatteryState.Charging
    readonly property bool usbCharger: chargerType.valid && chargerType.type === MceChargerType.USB
})QML",
              QUrl(QStringLiteral("mce.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    auto sub = [&](const char *name) { return o->property(name).value<QObject *>(); };

    // No MCE yet: nothing is valid.
    QVERIFY(!sub("display")->property("valid").toBool());
    QVERIFY(!sub("owner")->property("valid").toBool() || sub("owner")->property("nameOwner").toString().isEmpty());

    FakeMce mce;
    QVERIFY(mce.start());
    QTRY_VERIFY(sub("display")->property("valid").toBool());
    QVERIFY(o->property("displayOn").toBool());
    QTRY_VERIFY(sub("tklock")->property("valid").toBool());
    QVERIFY(!o->property("locked").toBool());
    QTRY_COMPARE(o->property("percent").toInt(), 57);
    QTRY_VERIFY(sub("cable")->property("valid").toBool());
    QVERIFY(!sub("cable")->property("connected").toBool());
    QTRY_VERIFY(sub("powerSave")->property("valid").toBool());
    QVERIFY(!sub("powerSave")->property("active").toBool());
    QTRY_VERIFY(sub("call")->property("valid").toBool());
    QVERIFY(!o->property("ringing").toBool());
    QTRY_VERIFY(!sub("owner")->property("nameOwner").toString().isEmpty());

    // MCE's signals.
    mce.emitSignal(QStringLiteral("display_status_ind"), { QStringLiteral("off") });
    QTRY_VERIFY(!o->property("displayOn").toBool());
    mce.emitSignal(QStringLiteral("tklock_mode_ind"), { QStringLiteral("locked") });
    QTRY_VERIFY(o->property("locked").toBool());
    mce.emitSignal(QStringLiteral("battery_level_ind"), { 12 });
    QTRY_COMPARE(o->property("percent").toInt(), 12);
    mce.emitSignal(QStringLiteral("battery_state_ind"), { QStringLiteral("charging") });
    QTRY_VERIFY(o->property("batteryCharging").toBool());
    mce.emitSignal(QStringLiteral("usb_cable_state_ind"), { QStringLiteral("connected") });
    QTRY_VERIFY(sub("cable")->property("connected").toBool());
    mce.emitSignal(QStringLiteral("charger_state_ind"), { QStringLiteral("on") });
    QTRY_VERIFY(sub("charger")->property("charging").toBool());
    mce.emitSignal(QStringLiteral("charger_type_ind"), { QStringLiteral("usb") });
    QTRY_VERIFY(o->property("usbCharger").toBool());
    mce.emitSignal(QStringLiteral("psm_state_ind"), { true });
    QTRY_VERIFY(sub("powerSave")->property("active").toBool());
    mce.emitSignal(QStringLiteral("sig_call_state_ind"), { QStringLiteral("ringing"), QStringLiteral("emergency") });
    QTRY_VERIFY(o->property("ringing").toBool());
    QVERIFY(o->property("emergency").toBool());

    // MCE leaves the bus: the state is no longer valid.
    mce.stop();
    QTRY_VERIFY(!sub("display")->property("valid").toBool());
    QTRY_VERIFY(!sub("batteryLevel")->property("valid").toBool());
}

int main(int argc, char **argv)
{
    // The private daemon stands in for the system bus, where MCE is.
    const QByteArray bus = qgetenv("DBUS_SESSION_BUS_ADDRESS");
    if (!bus.isEmpty())
        qputenv("DBUS_SYSTEM_BUS_ADDRESS", bus);
    QGuiApplication app(argc, argv);
    tst_Mce test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_mce.moc"
