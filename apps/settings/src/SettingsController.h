#pragma once

#include <QAbstractItemModel>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QtQmlIntegration>

class SettingsController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit SettingsController(QObject *parent = nullptr);

    Q_PROPERTY(int appSourceRevision READ appSourceRevision NOTIFY appSourceChanged)
    Q_PROPERTY(int defaultAppsRevision READ defaultAppsRevision NOTIFY defaultAppsChanged)
    Q_PROPERTY(QVariantList notificationApps READ notificationApps NOTIFY notificationAppsChanged)
    Q_PROPERTY(
        int notificationAppsRevision READ notificationAppsRevision NOTIFY notificationAppsChanged)
    Q_PROPERTY(QString osVersion READ osVersion NOTIFY systemInfoChanged)
    Q_PROPERTY(QString buildType READ buildType NOTIFY systemInfoChanged)
    Q_PROPERTY(QString kernelVersion READ kernelVersion NOTIFY systemInfoChanged)
    Q_PROPERTY(QString deviceModel READ deviceModel NOTIFY systemInfoChanged)
    Q_PROPERTY(QString displayResolution READ displayResolution NOTIFY systemInfoChanged)
    Q_PROPERTY(QString displayRefreshRate READ displayRefreshRate NOTIFY systemInfoChanged)
    Q_PROPERTY(QString displayDpi READ displayDpi NOTIFY systemInfoChanged)
    Q_PROPERTY(QString displayScale READ displayScale NOTIFY systemInfoChanged)
    Q_PROPERTY(QVariantList openSourceLicenses READ openSourceLicenses CONSTANT)
    Q_PROPERTY(bool wifiDialogVisible READ wifiDialogVisible NOTIFY wifiDialogChanged)
    Q_PROPERTY(QString wifiDialogSsid READ wifiDialogSsid NOTIFY wifiDialogChanged)
    Q_PROPERTY(int wifiDialogStrength READ wifiDialogStrength NOTIFY wifiDialogChanged)
    Q_PROPERTY(QString wifiDialogSecurity READ wifiDialogSecurity NOTIFY wifiDialogChanged)
    Q_PROPERTY(bool wifiDialogSecured READ wifiDialogSecured NOTIFY wifiDialogChanged)
    Q_PROPERTY(bool wifiDialogConnecting READ wifiDialogConnecting NOTIFY wifiDialogChanged)
    Q_PROPERTY(QString wifiDialogError READ wifiDialogError NOTIFY wifiDialogChanged)
    Q_PROPERTY(
        bool bluetoothDialogVisible READ bluetoothDialogVisible NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(QString bluetoothDialogName READ bluetoothDialogName NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(
        QString bluetoothDialogAddress READ bluetoothDialogAddress NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(QString bluetoothDialogType READ bluetoothDialogType NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(QString bluetoothDialogMode READ bluetoothDialogMode NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(
        QString bluetoothDialogPasskey READ bluetoothDialogPasskey NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(
        bool bluetoothDialogPairing READ bluetoothDialogPairing NOTIFY bluetoothDialogChanged)
    Q_PROPERTY(QString bluetoothDialogError READ bluetoothDialogError NOTIFY bluetoothDialogChanged)

    Q_INVOKABLE QVariantList appsForHandler(const QString &handler, int revision = 0);
    Q_INVOKABLE QString      defaultAppName(const QString &handler, int revision = 0);
    Q_INVOKABLE void         setDefaultApp(const QString &handler, const QString &appId);
    Q_INVOKABLE QVariantList notificationAppsForRevision(int revision = 0);
    Q_INVOKABLE void         setNotificationEnabled(const QString &appId, bool enabled);
    Q_INVOKABLE void         requestPage(const QString &pageName, const QVariantMap &params = {});
    Q_INVOKABLE bool         requestBack();
    Q_INVOKABLE void showWifiDialog(const QString &ssid, int strength, const QString &security,
                                    bool secured);
    Q_INVOKABLE void dismissWifiDialog();
    Q_INVOKABLE void submitWifiPassword(const QString &password);
    Q_INVOKABLE void showBluetoothDialog(const QString &name, const QString &address,
                                         const QString &type, const QString &mode);
    Q_INVOKABLE void showBluetoothPasskeyConfirmation(const QString &name, const QString &address,
                                                      const QString &type, quint32 passkey);
    Q_INVOKABLE void dismissBluetoothDialog();
    Q_INVOKABLE void submitBluetoothPin(const QString &pin);
    Q_INVOKABLE void submitBluetoothPasskey(const QString &passkey);
    Q_INVOKABLE void confirmBluetoothPairing(bool accepted);
    Q_INVOKABLE void cancelBluetoothPairing();
    Q_INVOKABLE QString bluetoothDeviceIcon(const QString &type) const;
    Q_INVOKABLE QString bluetoothPairingModeText(const QString &mode) const;
    Q_INVOKABLE QString bluetoothHelpText(const QString &mode) const;
    Q_INVOKABLE bool    bluetoothCanPair(const QString &mode, const QString &pin,
                                         const QString &passkey) const;
    Q_INVOKABLE QString batteryStatusText(bool isCharging, bool isPluggedIn,
                                          int estimatedSeconds) const;
    Q_INVOKABLE QString wifiSignalIcon(int strength) const;
    Q_INVOKABLE QString wifiConnectionStatusText(int strength) const;
    Q_INVOKABLE QString availableNetworkSubtitle(const QString &security, int strength,
                                                 const QVariant &frequency) const;
    Q_INVOKABLE QString authModeLabel(int authMode) const;
    Q_INVOKABLE QString lockoutStatusText(bool lockedOut, int secondsRemaining) const;
    Q_INVOKABLE QString quickPinValidationError(const QString &pin, const QString &password) const;
    Q_INVOKABLE QString soundTypeLabel(const QString &soundType) const;

    int                 navigationDepth() const;
    void                setNavigationDepth(int depth);
    int                 appSourceRevision() const;
    int                 defaultAppsRevision() const;
    int                 notificationAppsRevision() const;
    QVariantList        notificationApps() const;
    QString             osVersion() const;
    QString             buildType() const;
    QString             kernelVersion() const;
    QString             deviceModel() const;
    QString             displayResolution() const;
    QString             displayRefreshRate() const;
    QString             displayDpi() const;
    QString             displayScale() const;
    QVariantList        openSourceLicenses() const;
    bool                wifiDialogVisible() const;
    QString             wifiDialogSsid() const;
    int                 wifiDialogStrength() const;
    QString             wifiDialogSecurity() const;
    bool                wifiDialogSecured() const;
    bool                wifiDialogConnecting() const;
    QString             wifiDialogError() const;
    bool                bluetoothDialogVisible() const;
    QString             bluetoothDialogName() const;
    QString             bluetoothDialogAddress() const;
    QString             bluetoothDialogType() const;
    QString             bluetoothDialogMode() const;
    QString             bluetoothDialogPasskey() const;
    bool                bluetoothDialogPairing() const;
    QString             bluetoothDialogError() const;

  signals:
    void appSourceChanged();
    void defaultAppsChanged();
    void pageRequested(const QString &pageName, const QVariantMap &params);
    void backRequested();
    void navigationDepthChanged();
    void wifiDialogChanged();
    void bluetoothDialogChanged();
    void notificationAppsChanged();
    void systemInfoChanged();

  private slots:
    void                resolveDependencies();
    QVariantList        buildEligibleApps(const QString &handler) const;
    QString             findAppName(const QString &appId) const;
    QVariantMap         defaultAppsMap() const;
    void                updateDefaultApps(const QVariantMap &apps);
    QAbstractItemModel *appModel() const;
    int                 roleIndex(const QByteArray &roleName) const;
    void                handleAppSourceChanged();
    void                handleDefaultAppsChanged();
    void                handleNotificationSettingsChanged();
    void                updateSystemInfo();
    void                handleWifiConnectionSuccess();
    void                handleWifiConnectionFailed(const QString &message);
    void                handleBluetoothEnabledChanged();
    void                handleBluetoothPairingSucceeded(const QString &address);
    void                handleBluetoothPairingFailed(const QString &address, const QString &error);
    void                handleBluetoothPinRequested(const QString &address, const QString &name);
    void handleBluetoothPasskeyRequested(const QString &address, const QString &name);
    void handleBluetoothPasskeyConfirmation(const QString &address, const QString &name,
                                            quint32 passkey);
    void setWifiDialogVisible(bool visible);
    void setWifiDialogError(const QString &message);
    void setBluetoothDialogVisible(bool visible);
    void setBluetoothDialogError(const QString &message);

  private:
    QPointer<QObject>      m_settingsManager;
    QPointer<QObject>      m_appSource;
    QHash<int, QByteArray> m_roleNames;
    int                    m_navigationDepth          = 0;
    int                    m_appSourceRevision        = 0;
    int                    m_defaultAppsRevision      = 0;
    int                    m_notificationAppsRevision = 0;
    QPointer<QObject>      m_networkManager;
    QPointer<QObject>      m_bluetoothManager;
    bool                   m_wifiDialogVisible = false;
    QString                m_wifiDialogSsid;
    int                    m_wifiDialogStrength = 0;
    QString                m_wifiDialogSecurity;
    bool                   m_wifiDialogSecured    = true;
    bool                   m_wifiDialogConnecting = false;
    QString                m_wifiDialogError;
    bool                   m_bluetoothDialogVisible = false;
    QString                m_bluetoothDialogName;
    QString                m_bluetoothDialogAddress;
    QString                m_bluetoothDialogType;
    QString                m_bluetoothDialogMode;
    QString                m_bluetoothDialogPasskey;
    bool                   m_bluetoothDialogPairing = false;
    QString                m_bluetoothDialogError;
    QString                m_osVersion;
    QString                m_buildType;
    QString                m_kernelVersion;
    QString                m_deviceModel;
    QString                m_displayResolution;
    QString                m_displayRefreshRate;
    QString                m_displayDpi;
    QString                m_displayScale;
    QVariantList           m_openSourceLicenses;
};
