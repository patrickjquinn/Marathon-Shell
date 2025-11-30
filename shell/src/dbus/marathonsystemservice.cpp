#include "marathonsystemservice.h"
#include "../powermanagercpp.h"
#include "../networkmanagercpp.h"
#include "../displaymanagercpp.h"
#include "../audiomanagercpp.h"
#include <QDBusConnection>
#include <QSysInfo>
#include <QFile>
#include <QDebug>

MarathonSystemService::MarathonSystemService(PowerManagerCpp *power, NetworkManagerCpp *network,
                                             DisplayManagerCpp *display, AudioManagerCpp *audio,
                                             QObject *parent)
    : QObject(parent)
    , m_power(power)
    , m_network(network)
    , m_display(display)
    , m_audio(audio) {
    connect(m_power, &PowerManagerCpp::batteryLevelChanged, this,
            [this]() { emit BatteryChanged(batteryLevel(), batteryCharging()); });

    connect(m_network, &NetworkManagerCpp::wifiConnectedChanged, this,
            [this]() { emit NetworkChanged(networkConnected(), networkType()); });

    connect(m_network, &NetworkManagerCpp::ethernetConnectedChanged, this,
            [this]() { emit NetworkChanged(networkConnected(), networkType()); });
}

MarathonSystemService::~MarathonSystemService() {}

bool MarathonSystemService::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.marathon.SystemService")) {
        qWarning() << "[SystemService] Failed to register service:" << bus.lastError().message();
        return false;
    }

    if (!bus.registerObject("/org/marathon/SystemService", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals |
                                QDBusConnection::ExportAllProperties)) {
        qWarning() << "[SystemService] Failed to register object:" << bus.lastError().message();
        return false;
    }

    qInfo() << "[SystemService] ✓ Registered on D-Bus";
    return true;
}

int MarathonSystemService::batteryLevel() const {
    return m_power ? m_power->batteryLevel() : 0;
}

bool MarathonSystemService::batteryCharging() const {
    return m_power ? m_power->isCharging() : false;
}

QString MarathonSystemService::batteryState() const {
    if (!m_power)
        return "unknown";
    return m_power->isCharging() ? "charging" : "discharging";
}

bool MarathonSystemService::networkConnected() const {
    return m_network ? (m_network->wifiConnected() || m_network->ethernetConnected()) : false;
}

QString MarathonSystemService::networkType() const {
    if (!m_network)
        return "none";
    if (m_network->wifiConnected())
        return "wifi";
    if (m_network->ethernetConnected())
        return "ethernet";
    return "none";
}

int MarathonSystemService::signalStrength() const {
    return m_network ? m_network->wifiSignalStrength() : 0;
}

int MarathonSystemService::displayBrightness() const {
    // DisplayManagerCpp doesn't have a getter, return default
    return 100;
}

bool MarathonSystemService::displayAutoRotate() const {
    // Not implemented in DisplayManagerCpp
    return false;
}

int MarathonSystemService::displayOrientation() const {
    // Not implemented in DisplayManagerCpp
    return 0;
}

void MarathonSystemService::setDisplayBrightness(int brightness) {
    if (m_display) {
        m_display->setBrightness(static_cast<double>(brightness) / 100.0);
    }
}

void MarathonSystemService::setDisplayAutoRotate(bool enabled) {
    // Not implemented in DisplayManagerCpp
    Q_UNUSED(enabled);
}

QString MarathonSystemService::GetDeviceModel() {
    return QSysInfo::prettyProductName();
}

QString MarathonSystemService::GetOSVersion() {
    return QString("Marathon OS 1.0.0 (%1)").arg(QSysInfo::kernelVersion());
}

int MarathonSystemService::GetUptime() {
    QFile uptimeFile("/proc/uptime");
    if (uptimeFile.open(QIODevice::ReadOnly)) {
        QString     content = uptimeFile.readAll();
        QStringList parts   = content.split(' ');
        if (!parts.isEmpty()) {
            return static_cast<int>(parts[0].toDouble());
        }
    }
    return 0;
}

int MarathonSystemService::GetCPUUsage() {
    // TODO: Implement CPU usage calculation
    return 0;
}

int MarathonSystemService::GetMemoryUsage() {
    // TODO: Implement memory usage from /proc/meminfo
    return 0;
}

int MarathonSystemService::GetTotalMemory() {
    // TODO: Implement total memory from /proc/meminfo
    return 0;
}

bool MarathonSystemService::SetDisplayBrightness(int brightness) {
    setDisplayBrightness(brightness);
    return true;
}

bool MarathonSystemService::SetDisplayAutoRotate(bool enabled) {
    setDisplayAutoRotate(enabled);
    return true;
}

void MarathonSystemService::HapticFeedback(const QString &type) {
    qInfo() << "[SystemService] HapticFeedback:" << type;
    // TODO: Implement haptic feedback via hardware
}
