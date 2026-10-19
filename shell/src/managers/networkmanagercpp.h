#ifndef NETWORKMANAGERCPP_H
#define NETWORKMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QTimer>
#include <QHash>
#include <qqml.h>

class NetworkManagerCpp : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static NetworkManagerCpp *create(QQmlEngine *, QJSEngine *);
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
    Q_PROPERTY(bool airplaneModeEnabled READ airplaneModeEnabled NOTIFY airplaneModeEnabledChanged)
    Q_PROPERTY(bool hotspotActive READ isHotspotActive NOTIFY hotspotActiveChanged)
    Q_PROPERTY(
        QVariantList availableNetworks READ availableNetworks NOTIFY availableNetworksChanged)

  public:
    explicit NetworkManagerCpp(QObject *parent = nullptr);
    ~NetworkManagerCpp() override;

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
    }
    bool airplaneModeEnabled() const {
        return m_airplaneModeEnabled;
    }
    QVariantList availableNetworks() const {
        return m_availableNetworks;
    }

    Q_INVOKABLE void         enableWifi();
    Q_INVOKABLE void         disableWifi();
    Q_INVOKABLE void         toggleWifi();
    Q_INVOKABLE void         scanWifi();
    Q_INVOKABLE void         connectToNetwork(const QString &ssid, const QString &password);
    Q_INVOKABLE void         disconnectWifi();
    // Abandons a connectToNetwork that has not reached ACTIVATED yet.
    Q_INVOKABLE void         cancelPendingConnection();
    // Drops every saved profile for ssid.
    Q_INVOKABLE void         forgetNetwork(const QString &ssid);
    // security: "none", "wpa-psk" or "sae".
    Q_INVOKABLE void         connectToHiddenNetwork(const QString &ssid, const QString &security,
                                                    const QString &password);

    Q_INVOKABLE void         setAirplaneMode(bool enabled);

    Q_INVOKABLE void         createHotspot(const QString &ssid, const QString &password);
    Q_INVOKABLE void         stopHotspot();
    Q_INVOKABLE bool         isHotspotActive() const;

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
    void airplaneModeEnabledChanged();
    void networkError(const QString &message);
    void availableNetworksChanged();
    void connectionSuccess();
    void connectionFailed(const QString &message);
    void hotspotActiveChanged();
    void hotspotFailed(const QString &message);

  private slots:
    void queryWifiState();
    void queryConnectionState();
    void updateWifiSignalStrength();
    void updateWifiDetails();
    void scanAccessPoints();
    void onNmPropertiesChanged(const QString &interface, const QVariantMap &changed,
                               const QStringList &invalidated);
    void onApPropertiesChanged(const QString &interface, const QVariantMap &changed,
                               const QStringList &invalidated);
    void onHotspotStateChanged(uint state, uint reason);
    void refreshSavedNetworks();
    void onPendingActivationStateChanged(uint state, uint reason);

  private:
    void            setupDBusConnections();
    void            detectHardwareAvailability();
    void            setHotspotActive(bool active);
    void            watchHotspot(bool watch);
    void            activate(const QDBusMessage &msg, const QString &ssid);
    void            watchPendingActivation(const QString &path);
    void            markKnownNetworks();
    void            publishAccessPoints(QVariantList networks);
    void            addAccessPoint(QVariantList &networks, const QString &apPath,
                                   const QVariantMap &props) const;
    void            setWifiEnabled(bool enabled);

    QDBusInterface *m_nmInterface;
    QTimer         *m_signalMonitor = nullptr;

    bool            m_wifiEnabled;
    bool            m_wifiConnected;
    QString         m_wifiSsid;
    // SSID we last asked NetworkManager to activate but haven't yet seen
    // come online via PropertiesChanged. Used to fire connectionSuccess
    // on real activation rather than the eager AddAndActivateConnection
    // reply — without that gating the WiFi password dialog dismisses
    // before authentication completes.
    QString      m_pendingConnectSsid;
    QString      m_pendingConnectPath;
    bool         m_connectCancelled = false;
    QString      m_watchedActivationPath;
    // Saved infrastructure Wi-Fi profiles by SSID.
    QHash<QString, QStringList> m_savedNetworks;
    int                         m_savedGeneration = 0;
    int                         m_scanGeneration  = 0;
    int          m_wifiSignalStrength;
    bool         m_ethernetConnected;
    QString      m_ethernetConnectionName;
    QString      m_activeWifiDevicePath;
    QString      m_activeApPath;
    bool         m_airplaneModeEnabled;
    bool         m_wifiAvailable;
    bool         m_bluetoothAvailable;
    bool         m_hasNetworkManager;
    QVariantList m_availableNetworks;
    QString      m_wifiDevicePath;
    QTimer      *m_scanTimer;
    QString      m_hotspotConnectionPath;
    bool         m_hotspotActive;
};

#endif
