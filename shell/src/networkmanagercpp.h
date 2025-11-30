#ifndef NETWORKMANAGERCPP_H
#define NETWORKMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QTimer>

class NetworkManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiSsidChanged)
    Q_PROPERTY(int wifiSignalStrength READ wifiSignalStrength NOTIFY wifiSignalStrengthChanged)
    Q_PROPERTY(bool ethernetConnected READ ethernetConnected NOTIFY ethernetConnectedChanged)
    Q_PROPERTY(QString ethernetConnectionName READ ethernetConnectionName NOTIFY
                   ethernetConnectionNameChanged)
    Q_PROPERTY(bool wifiAvailable READ wifiAvailable NOTIFY wifiAvailableChanged)
    Q_PROPERTY(bool bluetoothAvailable READ bluetoothAvailable NOTIFY bluetoothAvailableChanged)
    Q_PROPERTY(bool hotspotSupported READ hotspotSupported NOTIFY hotspotSupportedChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY bluetoothEnabledChanged)
    Q_PROPERTY(bool airplaneModeEnabled READ airplaneModeEnabled NOTIFY airplaneModeEnabledChanged)
    Q_PROPERTY(
        QVariantList availableNetworks READ availableNetworks NOTIFY availableNetworksChanged)

  public:
    explicit NetworkManagerCpp(QObject *parent = nullptr);
    ~NetworkManagerCpp();

    bool wifiEnabled() const {
        return m_wifiEnabled;
    }
    bool wifiConnected() const {
        return m_wifiConnected;
    }
    QString wifiSsid() const {
        return m_wifiSsid;
    }
    int wifiSignalStrength() const {
        return m_wifiSignalStrength;
    }
    bool ethernetConnected() const {
        return m_ethernetConnected;
    }
    QString ethernetConnectionName() const {
        return m_ethernetConnectionName;
    }
    bool wifiAvailable() const {
        return m_wifiAvailable;
    }
    bool bluetoothAvailable() const {
        return m_bluetoothAvailable;
    }
    bool hotspotSupported() const {
        return m_wifiAvailable;
    } // Hotspot requires WiFi hardware
    bool bluetoothEnabled() const {
        return m_bluetoothEnabled;
    }
    bool airplaneModeEnabled() const {
        return m_airplaneModeEnabled;
    }
    QVariantList availableNetworks() const {
        return m_availableNetworks;
    }

    Q_INVOKABLE void enableWifi();
    Q_INVOKABLE void disableWifi();
    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectToNetwork(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectWifi();

    Q_INVOKABLE void enableBluetooth();
    Q_INVOKABLE void disableBluetooth();
    Q_INVOKABLE void toggleBluetooth();

    Q_INVOKABLE void setAirplaneMode(bool enabled);

    // WiFi Hotspot
    Q_INVOKABLE void createHotspot(const QString &ssid, const QString &password);
    Q_INVOKABLE void stopHotspot();
    Q_INVOKABLE bool isHotspotActive() const;

    // VPN Management
    Q_INVOKABLE QVariantList getVpnConnections();
    Q_INVOKABLE void         connectVpn(const QString &connectionId);
    Q_INVOKABLE void         disconnectVpn(const QString &connectionId);
    Q_INVOKABLE bool         isVpnConnected(const QString &connectionId);

  signals:
    void wifiEnabledChanged();
    void wifiConnectedChanged();
    void wifiSsidChanged();
    void wifiSignalStrengthChanged();
    void ethernetConnectedChanged();
    void ethernetConnectionNameChanged();
    void wifiAvailableChanged();
    void bluetoothAvailableChanged();
    void hotspotSupportedChanged();
    void bluetoothEnabledChanged();
    void airplaneModeEnabledChanged();
    void networkError(const QString &message);
    void availableNetworksChanged();
    void connectionSuccess();
    void connectionFailed(const QString &message);

  private slots:
    void queryWifiState();
    void queryConnectionState();
    void updateWifiSignalStrength();
    void updateWifiDetails();
    void scanAccessPoints();
    void processAccessPoint(const QString &apPath);

  private:
    void            setupDBusConnections();
    void            detectHardwareAvailability();

    QDBusInterface *m_nmInterface;
    QTimer         *m_signalMonitor;
    QTimer         *m_connectionMonitor;

    bool            m_wifiEnabled;
    bool            m_wifiConnected;
    QString         m_wifiSsid;
    int             m_wifiSignalStrength;
    bool            m_ethernetConnected;
    QString         m_ethernetConnectionName;
    QString         m_activeWifiDevicePath;
    QString         m_activeApPath;
    bool            m_bluetoothEnabled;
    bool            m_airplaneModeEnabled;
    bool            m_wifiAvailable;
    bool            m_bluetoothAvailable;
    bool            m_hasNetworkManager;
    QVariantList    m_availableNetworks;
    QString         m_wifiDevicePath;
    QTimer         *m_scanTimer;
    QString         m_hotspotConnectionPath;
    bool            m_hotspotActive;
};

#endif // NETWORKMANAGERCPP_H
