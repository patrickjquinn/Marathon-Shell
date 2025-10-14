#ifndef NETWORKMANAGERCPP_H
#define NETWORKMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QTimer>

class NetworkManagerCpp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiSsidChanged)
    Q_PROPERTY(int wifiSignalStrength READ wifiSignalStrength NOTIFY wifiSignalStrengthChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY bluetoothEnabledChanged)
    Q_PROPERTY(bool airplaneModeEnabled READ airplaneModeEnabled NOTIFY airplaneModeEnabledChanged)

public:
    explicit NetworkManagerCpp(QObject* parent = nullptr);
    ~NetworkManagerCpp();

    bool wifiEnabled() const { return m_wifiEnabled; }
    bool wifiConnected() const { return m_wifiConnected; }
    QString wifiSsid() const { return m_wifiSsid; }
    int wifiSignalStrength() const { return m_wifiSignalStrength; }
    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    bool airplaneModeEnabled() const { return m_airplaneModeEnabled; }

    Q_INVOKABLE void enableWifi();
    Q_INVOKABLE void disableWifi();
    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectToNetwork(const QString& ssid, const QString& password);
    Q_INVOKABLE void disconnectWifi();
    
    Q_INVOKABLE void enableBluetooth();
    Q_INVOKABLE void disableBluetooth();
    Q_INVOKABLE void toggleBluetooth();
    
    Q_INVOKABLE void setAirplaneMode(bool enabled);

signals:
    void wifiEnabledChanged();
    void wifiConnectedChanged();
    void wifiSsidChanged();
    void wifiSignalStrengthChanged();
    void bluetoothEnabledChanged();
    void airplaneModeEnabledChanged();
    void networkError(const QString& message);

private:
    void setupDBusConnections();
    void queryWifiState();
    void updateWifiSignalStrength();

    QDBusInterface* m_nmInterface;
    QTimer* m_signalMonitor;
    
    bool m_wifiEnabled;
    bool m_wifiConnected;
    QString m_wifiSsid;
    int m_wifiSignalStrength;
    bool m_bluetoothEnabled;
    bool m_airplaneModeEnabled;
    bool m_hasNetworkManager;
};

#endif // NETWORKMANAGERCPP_H

