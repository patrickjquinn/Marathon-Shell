#pragma once

#include <QObject>
#include <QString>
#include <QVariant>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QTimer>

#include <QTimer>
#include <QMap>
#include <QVariant>
#include <QDBusObjectPath>

// Define types for GetManagedObjects return value
typedef QMap<QString, QVariant>             PropertyMap;
typedef QMap<QString, PropertyMap>          InterfaceMap;
typedef QMap<QDBusObjectPath, InterfaceMap> ManagedObjectMap;
Q_DECLARE_METATYPE(ManagedObjectMap)

class BluetoothAgent;

class BluetoothDevice : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString address READ address CONSTANT)
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)
    Q_PROPERTY(QString alias READ alias NOTIFY aliasChanged)
    Q_PROPERTY(bool paired READ paired NOTIFY pairedChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool trusted READ trusted NOTIFY trustedChanged)
    Q_PROPERTY(int rssi READ rssi NOTIFY rssiChanged)
    Q_PROPERTY(QString icon READ icon NOTIFY iconChanged)

  public:
    explicit BluetoothDevice(const QString &path, QObject *parent = nullptr);

    QString address() const {
        return m_address;
    }
    QString name() const {
        return m_name;
    }
    QString alias() const {
        return m_alias;
    }
    bool paired() const {
        return m_paired;
    }
    bool connected() const {
        return m_connected;
    }
    bool trusted() const {
        return m_trusted;
    }
    int rssi() const {
        return m_rssi;
    }
    QString icon() const {
        return m_icon;
    }
    QString path() const {
        return m_path;
    }

    void updateProperties();

  signals:
    void nameChanged();
    void aliasChanged();
    void pairedChanged();
    void connectedChanged();
    void trustedChanged();
    void rssiChanged();
    void iconChanged();

  private:
    QString m_path;
    QString m_address;
    QString m_name;
    QString m_alias;
    bool    m_paired    = false;
    bool    m_connected = false;
    bool    m_trusted   = false;
    int     m_rssi      = 0;
    QString m_icon;
};

class BluetoothManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(bool discoverable READ discoverable WRITE setDiscoverable NOTIFY discoverableChanged)
    Q_PROPERTY(QList<QObject *> devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(QList<QObject *> pairedDevices READ pairedDevices NOTIFY pairedDevicesChanged)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY adapterNameChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

  public:
    explicit BluetoothManager(QObject *parent = nullptr);
    ~BluetoothManager() override;

    bool enabled() const {
        return m_enabled;
    }
    void setEnabled(bool enabled);

    bool scanning() const {
        return m_scanning;
    }
    bool discoverable() const {
        return m_discoverable;
    }
    void             setDiscoverable(bool discoverable);

    QList<QObject *> devices() const {
        return m_devices;
    }
    QList<QObject *> pairedDevices() const;

    QString          adapterName() const {
        return m_adapterName;
    }
    bool available() const {
        return m_available;
    }

    Q_INVOKABLE void startScan();
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void pairDevice(const QString &address, const QString &pin = "");
    Q_INVOKABLE void unpairDevice(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);
    Q_INVOKABLE void trustDevice(const QString &address, bool trusted);
    Q_INVOKABLE void removeDevice(const QString &address);
    Q_INVOKABLE void cancelPairing(const QString &address);
    Q_INVOKABLE void confirmPairing(const QString &address, bool confirmed);

  signals:
    void enabledChanged();
    void scanningChanged();
    void discoverableChanged();
    void devicesChanged();
    void pairedDevicesChanged();
    void adapterNameChanged();
    void availableChanged();
    void pairingFailed(const QString &address, const QString &error);
    void pairingSucceeded(const QString &address);
    // Pairing interaction signals (forwarded from agent)
    void pinRequested(const QString &address, const QString &deviceName);
    void passkeyRequested(const QString &address, const QString &deviceName);
    void passkeyConfirmation(const QString &address, const QString &deviceName, quint32 passkey);

  private slots:
    void onDeviceAdded(const QDBusObjectPath &objectPath, const InterfaceMap &interfaces);
    void onDeviceRemoved(const QDBusObjectPath &objectPath, const QStringList &interfaces);
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);
    void updateAdapterProperties();
    void refreshDevices();

    void connectToBlueZ();
    BluetoothDevice *findDeviceByPath(const QString &path);
    BluetoothDevice *findDeviceByAddress(const QString &address);
    void             addDevice(const QString &path);
    void             removeDeviceByPath(const QString &path);

  private:
    void             initializeAdapter();

    QDBusConnection  m_bus;
    QDBusInterface  *m_adapter = nullptr;
    QString          m_adapterPath;
    QString          m_adapterName;
    bool             m_enabled      = false;
    bool             m_scanning     = false;
    bool             m_discoverable = false;
    bool             m_available    = false;
    QList<QObject *> m_devices;
    QTimer          *m_scanTimer = nullptr;
    BluetoothAgent  *m_agent     = nullptr;
};
