#pragma once

#include <QObject>
#include <QAbstractListModel>
#include <QDBusInterface>
#include <QDBusVariant>
#include <QDateTime>
#include <QElapsedTimer>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

class Audio;
namespace marathon::platform {
    class Display;
    class Network;
    class Power;
    class Settings;
}

class CallHistoryClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int count READ count NOTIFY historyChanged)

  public:
    explicit CallHistoryClient(QObject *parent = nullptr);

    QVariantList history() const {
        return m_history;
    }
    int count() const {
        return static_cast<int>(m_history.size());
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         addCall(const QString &number, const QString &type, qint64 timestamp,
                                     int duration);
    Q_INVOKABLE void         deleteCall(int id);
    Q_INVOKABLE void         clearHistory();
    Q_INVOKABLE QVariantMap  getCallById(int id);
    Q_INVOKABLE QVariantList getCallsByNumber(const QString &number);

  signals:
    void historyChanged();
    void callAdded(int id);

  private:
    void           setHistory(const QVariantList &v);
    QDBusInterface m_iface;
    QVariantList   m_history;
};

class MediaLibraryClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int photoCount READ photoCount NOTIFY libraryChanged)
    Q_PROPERTY(int videoCount READ videoCount NOTIFY libraryChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)

  public:
    explicit MediaLibraryClient(const QString &appId, QObject *parent = nullptr);

    QVariantList albums() const {
        return m_albums;
    }
    bool isScanning() const {
        return m_isScanning;
    }
    int photoCount() const {
        return m_photoCount;
    }
    int videoCount() const {
        return m_videoCount;
    }
    int scanProgress() const {
        return m_scanProgress;
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         scanLibrary();
    Q_INVOKABLE void         scanLibraryAsync();
    Q_INVOKABLE QVariantList getPhotos(const QString &albumId);
    Q_INVOKABLE QVariantList getAllPhotos();
    Q_INVOKABLE QVariantList getVideos();
    Q_INVOKABLE QString      generateThumbnail(const QString &filePath);
    Q_INVOKABLE void         deleteMedia(int mediaId);

  signals:
    void albumsChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int photoCount, int videoCount);
    void newMediaAdded(const QString &path);
    void libraryChanged();
    void scanProgressChanged(int progress);

  private slots:
    void setScanning(bool scanning);
    void setScanProgress(int progress);
    void onLibraryChanged();

  private:
    bool           ensureStoragePermission();
    void           setAlbums(const QVariantList &v);

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;

    QVariantList   m_albums;
    bool           m_isScanning       = false;
    int            m_photoCount       = 0;
    int            m_videoCount       = 0;
    int            m_scanProgress     = 0;
    bool           m_storageRequested = false;
};

class SecurityClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(int authMode READ authMode NOTIFY stateChanged)
    Q_PROPERTY(bool hasQuickPIN READ hasQuickPIN NOTIFY stateChanged)
    Q_PROPERTY(bool fingerprintAvailable READ fingerprintAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool isLockedOut READ isLockedOut NOTIFY stateChanged)
    Q_PROPERTY(int lockoutSecondsRemaining READ lockoutSecondsRemaining NOTIFY stateChanged)
    Q_PROPERTY(int failedAttempts READ failedAttempts NOTIFY stateChanged)
    Q_PROPERTY(bool canEraseAllContent READ canEraseAllContent NOTIFY stateChanged)
    Q_PROPERTY(QString dataEncryption READ dataEncryption NOTIFY stateChanged)

  public:
    explicit SecurityClient(const QString &appId, QObject *parent = nullptr);

    int                 authMode() const;
    bool                hasQuickPIN() const;
    bool                fingerprintAvailable() const;
    bool                isLockedOut() const;
    int                 lockoutSecondsRemaining() const;
    int                 failedAttempts() const;
    bool                canEraseAllContent() const;
    QString             dataEncryption() const;

    Q_INVOKABLE void    setQuickPIN(const QString &pin, const QString &systemPassword);
    Q_INVOKABLE void    removeQuickPIN(const QString &systemPassword);
    Q_INVOKABLE void    authenticatePassword(const QString &password);
    Q_INVOKABLE void    authenticateQuickPIN(const QString &pin);
    Q_INVOKABLE void    authenticateBiometric(int type);
    Q_INVOKABLE void    cancelAuthentication();
    Q_INVOKABLE void    resetLockout();
    Q_INVOKABLE bool    isBiometricEnrolled(int type);
    Q_INVOKABLE QString currentUsername();
    // The device restarts and erases itself, or eraseFailed() says why not.
    Q_INVOKABLE void    eraseAllContent(const QString &secret);

  signals:
    void stateChanged();
    void authenticationFailed(const QString &reason);
    void authenticationSuccess();
    void quickPINChanged();
    void eraseFailed(const QString &reason);

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureSystemPermission();
    void           refresh();
    QVariant       v(const QString &k, const QVariant &fallback = QVariant()) const;

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class BluetoothClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY stateChanged)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY stateChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY stateChanged)
    Q_PROPERTY(QVariantList pairedDevices READ pairedDevices NOTIFY stateChanged)

  public:
    explicit BluetoothClient(const QString &appId, QObject *parent = nullptr);

    bool             available() const;
    bool             enabled() const;
    void             setEnabled(bool enabled);
    bool             scanning() const;
    QString          adapterName() const;
    QVariantList     devices() const;
    QVariantList     pairedDevices() const;

    Q_INVOKABLE void startScan();
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void pairDevice(const QString &address, const QString &pin = QString());
    Q_INVOKABLE void unpairDevice(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);
    Q_INVOKABLE void confirmPairing(const QString &address, bool confirmed);
    Q_INVOKABLE void cancelPairing(const QString &address);

  signals:
    void stateChanged();
    void pairingFailed(const QString &address, const QString &error);
    void pairingSucceeded(const QString &address);
    void pinRequested(const QString &address, const QString &deviceName);
    void passkeyRequested(const QString &address, const QString &deviceName);
    void passkeyConfirmation(const QString &address, const QString &deviceName, quint32 passkey);

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureSystemPermission();
    void           refresh();

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class NavigationClient : public QObject {
    Q_OBJECT

  public:
    explicit NavigationClient(QObject *parent = nullptr);

    Q_INVOKABLE bool launchApp(const QString &appId);
    Q_INVOKABLE bool navigate(const QString &uri);
    Q_INVOKABLE bool launchAppWithRoute(const QString &appId, const QString &route,
                                        const QString &paramsJson = QString());

  signals:
    void appLaunched(const QString &appId);
    void navigationFailed(const QString &uri, const QString &error);
    void deepLinkRequested(const QString &appId, const QString &route, const QVariantMap &params);
    void settingsNavigationRequested(const QString &page, const QString &subpage,
                                     const QVariantMap &params);

  private slots:
    void onDeepLinkRequested(const QString &appId, const QString &route,
                             const QString &paramsJson);

  private:
    QDBusInterface m_iface;
};

class SystemStatusStoreClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(QString wifiNetwork READ wifiNetwork NOTIFY wifiNetworkChanged)

  public:
    explicit SystemStatusStoreClient(marathon::platform::Power *powerClient, marathon::platform::Network *networkClient,
                                     QObject *parent = nullptr);

    int batteryLevel() const {
        return m_batteryLevel;
    }
    bool wifiConnected() const {
        return m_wifiConnected;
    }
    QString wifiNetwork() const {
        return m_wifiNetwork;
    }

  signals:
    void batteryLevelChanged();
    void wifiConnectedChanged();
    void wifiNetworkChanged();

  private:
    void           refreshPower();
    void           refreshNetwork();
    void           setBatteryLevel(int level);
    void           setWifiConnected(bool connected);
    void           setWifiNetwork(const QString &network);

    marathon::platform::Power *m_powerClient;
    marathon::platform::Network *m_networkClient;
    int            m_batteryLevel  = 0;
    bool           m_wifiConnected = false;
    QString        m_wifiNetwork;
};

class SystemControlStoreClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isWifiOn READ isWifiOn NOTIFY isWifiOnChanged)
    Q_PROPERTY(bool isBluetoothOn READ isBluetoothOn NOTIFY isBluetoothOnChanged)
    Q_PROPERTY(bool isAirplaneModeOn READ isAirplaneModeOn NOTIFY isAirplaneModeOnChanged)
    Q_PROPERTY(bool isRotationLocked READ isRotationLocked NOTIFY isRotationLockedChanged)
    Q_PROPERTY(bool isDndMode READ isDndMode NOTIFY isDndModeChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)

  public:
    explicit SystemControlStoreClient(marathon::platform::Network *networkClient,
                                      BluetoothClient *bluetoothClient,
                                      marathon::platform::Display *displayClient, marathon::platform::Settings *settingsClient,
                                      Audio *audioClient, QObject *parent = nullptr);

    bool isWifiOn() const {
        return m_isWifiOn;
    }
    bool isBluetoothOn() const {
        return m_isBluetoothOn;
    }
    bool isAirplaneModeOn() const {
        return m_isAirplaneModeOn;
    }
    bool isRotationLocked() const {
        return m_isRotationLocked;
    }
    bool isDndMode() const {
        return m_isDndMode;
    }
    int brightness() const {
        return m_brightness;
    }
    int volume() const {
        return m_volume;
    }

    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void toggleBluetooth();
    Q_INVOKABLE void toggleAirplaneMode();
    Q_INVOKABLE void toggleRotationLock();
    Q_INVOKABLE void toggleDndMode();
    Q_INVOKABLE void setBrightness(int value);
    Q_INVOKABLE void setVolume(int value);

  signals:
    void isWifiOnChanged();
    void isBluetoothOnChanged();
    void isAirplaneModeOnChanged();
    void isRotationLockedChanged();
    void isDndModeChanged();
    void brightnessChanged();
    void volumeChanged();

  private:
    void             refreshNetwork();
    void             refreshBluetooth();
    void             refreshDisplay();
    void             refreshSettings();
    void             refreshAudio();

    void             setIsWifiOn(bool enabled);
    void             setIsBluetoothOn(bool enabled);
    void             setIsAirplaneModeOn(bool enabled);
    void             setIsRotationLocked(bool locked);
    void             setIsDndMode(bool enabled);
    void             setBrightnessValue(int value);
    void             setVolumeValue(int value);

    marathon::platform::Network *m_networkClient;
    BluetoothClient *m_bluetoothClient;
    marathon::platform::Display *m_displayClient;
    marathon::platform::Settings *m_settingsClient;
    Audio           *m_audioClient;
    bool             m_isWifiOn         = true;
    bool             m_isBluetoothOn    = false;
    bool             m_isAirplaneModeOn = false;
    bool             m_isRotationLocked = false;
    bool             m_isDndMode        = false;
    int              m_brightness       = 50;
    int              m_volume           = 50;
};

class HapticClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

  public:
    explicit HapticClient(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }

    Q_INVOKABLE void light();
    Q_INVOKABLE void medium();
    Q_INVOKABLE void heavy();
    Q_INVOKABLE void vibrate(int duration);
    Q_INVOKABLE void vibratePattern(const QVariantList &pattern, int repeat = 1);
    Q_INVOKABLE void stopVibration();

  signals:
    void availableChanged();

  private:
    void           refresh();
    QDBusInterface m_iface;
    bool           m_available = false;
};

class NotificationClient : public QObject {
    Q_OBJECT

  public:
  public:
    explicit NotificationClient(const QString &appId, QObject *parent = nullptr);

    Q_INVOKABLE int  sendNotification(const QString &appId, const QString &title,
                                      const QString     &body,
                                      const QVariantMap &options = QVariantMap());
    Q_INVOKABLE void dismissNotification(int id);
    Q_INVOKABLE void dismissAllNotifications();

  signals:
    void notificationClosed(int id, int reason);
    void actionInvoked(int id, const QString &action);

  private:
    bool           ensurePermission();
    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    bool           m_permissionRequested = false;
};

class UpdateClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString currentVersion READ currentVersion NOTIFY stateChanged)
    Q_PROPERTY(QString osVersion READ osVersion NOTIFY stateChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY stateChanged)
    Q_PROPERTY(qlonglong downloadSize READ downloadSize NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(QString blockedReason READ blockedReason NOTIFY stateChanged)
    Q_PROPERTY(QString rolledBackVersion READ rolledBackVersion NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(qlonglong lastCheckedMs READ lastCheckedMs NOTIFY stateChanged)
    Q_PROPERTY(bool autoUpdate READ autoUpdate WRITE setAutoUpdate NOTIFY stateChanged)
    Q_PROPERTY(bool restartScheduled READ restartScheduled NOTIFY stateChanged)
    Q_PROPERTY(QString currentReleaseNotes READ currentReleaseNotes NOTIFY stateChanged)

  public:
    explicit UpdateClient(QObject *parent = nullptr);

    QString state() const {
        return m_state.value("state").toString();
    }
    QString currentVersion() const {
        return m_state.value("currentVersion").toString();
    }
    QString osVersion() const {
        return m_state.value("osVersion").toString();
    }
    QString availableVersion() const {
        return m_state.value("availableVersion").toString();
    }
    qlonglong downloadSize() const {
        return m_state.value("downloadSize", -1).toLongLong();
    }
    QString releaseNotes() const {
        return m_state.value("releaseNotes").toString();
    }
    int progress() const {
        return m_state.value("progress").toInt();
    }
    QString blockedReason() const {
        return m_state.value("blockedReason").toString();
    }
    QString rolledBackVersion() const {
        return m_state.value("rolledBackVersion").toString();
    }
    bool updateAvailable() const {
        return state() == QLatin1String("available");
    }
    QString lastError() const {
        return m_state.value("lastError").toString();
    }
    qlonglong lastCheckedMs() const {
        return m_state.value("lastCheckedMs").toLongLong();
    }
    bool autoUpdate() const {
        return m_state.value("autoUpdate", true).toBool();
    }
    void setAutoUpdate(bool on);
    bool restartScheduled() const {
        return m_state.value("restartScheduled").toBool();
    }
    QString currentReleaseNotes() const {
        return m_state.value("currentReleaseNotes").toString();
    }

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void install();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void scheduleRestart();
    Q_INVOKABLE void refresh();

  signals:
    void stateChanged();

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    QDBusInterface m_iface;
    QVariantMap    m_state;
};

class DavClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    Q_PROPERTY(int accountCount READ accountCount NOTIFY accountsChanged)
    Q_PROPERTY(bool syncing READ syncing NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(qlonglong lastSyncMs READ lastSyncMs NOTIFY stateChanged)

  public:
    explicit DavClient(QObject *parent = nullptr);

    QVariantList accounts() const {
        return m_accounts;
    }
    int accountCount() const {
        return static_cast<int>(m_accounts.size());
    }
    bool syncing() const {
        return m_state.value("syncing").toBool();
    }
    QString lastError() const {
        return m_state.value("lastError").toString();
    }
    qlonglong lastSyncMs() const {
        return m_state.value("lastSyncMs").toLongLong();
    }

    Q_INVOKABLE QString addAccount(const QString &displayName, const QString &baseUrl,
                                   const QString &username, const QString &secret,
                                   const QString &authKind);
    Q_INVOKABLE bool    removeAccount(const QString &id);
    Q_INVOKABLE void    enableAccount(const QString &id, bool enabled);
    Q_INVOKABLE void    syncNow();
    Q_INVOKABLE void    refresh();

  signals:
    void accountsChanged();
    void stateChanged();
    void syncFinished(const QString &accountId);
    void accountDiscovered(const QString &accountId);
    void accountDiscoveryFailed(const QString &accountId, const QString &reason);

  private slots:
    void onAccountsChanged();
    void onStateChanged(const QVariantMap &state);
    void onSyncFinished(const QString &accountId);

  private:
    void           refreshAccounts();
    void           refreshState();

    QDBusInterface m_iface;
    QVariantList   m_accounts;
    QVariantMap    m_state;
};

// Uninstalls through the shell's AppStore1: user installs are bound read-only
// into the sandbox. uninstallComplete and uninstallFailed answer this
// client's own requests; appRemoved reports every uninstall the shell makes.
class AppInstallerClient : public QObject {
    Q_OBJECT

  public:
    explicit AppInstallerClient(QObject *parent = nullptr);

    Q_INVOKABLE bool canUninstall(const QString &appId);
    Q_INVOKABLE void uninstallApp(const QString &appId);

  signals:
    void uninstallComplete(const QString &appId);
    void uninstallFailed(const QString &appId, const QString &error);
    void appRemoved(const QString &appId);

  private slots:
    void onUninstallComplete(const QString &appId);
    void onUninstallFailed(const QString &appId, const QString &error);

  private:
    QDBusInterface m_iface;
    QSet<QString>  m_pending;
    // A list delegate asks on every creation; the shell rate-limits callers.
    QHash<QString, bool> m_removable;
};

// AppStoreClient — wraps org.marathonos.Shell.AppStore1 so the Store app
// can browse the catalog and request downloads. Read methods are
// synchronous DBus calls; download methods are fire-and-forget with
// progress / completion signals routed back via DBus signals so the UI
// can wire a Connections {} block to update progress bars and update
// rows live.
class AppStoreClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool catalogLoaded READ catalogLoaded NOTIFY stateChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(QString repositoryUrl READ repositoryUrl NOTIFY stateChanged)

  public:
    explicit AppStoreClient(QObject *parent = nullptr);

    bool catalogLoaded() const {
        return m_state.value("catalogLoaded").toBool();
    }
    bool loading() const {
        return m_state.value("loading").toBool();
    }
    QString repositoryUrl() const {
        return m_state.value("repositoryUrl").toString();
    }

    Q_INVOKABLE void         refreshCatalog();
    Q_INVOKABLE QVariantList searchApps(const QString &query = QString());
    Q_INVOKABLE QVariantMap  getApp(const QString &appId);
    Q_INVOKABLE QVariantList getFeaturedApps();
    Q_INVOKABLE QVariantList getAppsByCategory(const QString &category);
    Q_INVOKABLE QVariantList getAvailableUpdates();
    Q_INVOKABLE void         checkForUpdates();
    Q_INVOKABLE void         downloadApp(const QString &appId);
    Q_INVOKABLE void         cancelDownload(const QString &appId);
    Q_INVOKABLE void         refresh();

  signals:
    void stateChanged();
    void catalogRefreshed();
    void downloadProgress(const QString &appId, qint64 bytesReceived, qint64 bytesTotal);
    void downloadComplete(const QString &appId, const QString &packagePath);
    void downloadFailed(const QString &appId, const QString &error);

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    QDBusInterface m_iface;
    QVariantMap    m_state;
};

// Client for org.marathonos.Shell.AppLifecycle1 — lets the app declare
// active background work (turn-by-turn navigation, recording, downloads)
// so the shell's lifecycle layer keeps the runner warm. The category must
// be listed in the app's manifest backgroundCapabilities or the shell
// rejects the claim.
//
// Usage from QML:
//   property int navHandle: 0
//   onActiveNavigationChanged: {
//     if (activeNavigation && navHandle === 0)
//       navHandle = AppLifecycle.beginBackgroundTask("active-navigation", "route XYZ")
//     else if (!activeNavigation && navHandle !== 0) {
//       AppLifecycle.endBackgroundTask(navHandle); navHandle = 0
//     }
//   }
class AppLifecycleClient : public QObject {
    Q_OBJECT

  public:
    explicit AppLifecycleClient(QObject *parent = nullptr);

    // Returns a handle (>0) on accept, 0 on rejection (category not in
    // manifest, shell unreachable). The handle must be passed back to
    // endBackgroundTask when the work finishes — otherwise the capability
    // stays held until the runner exits, and the shell will refuse to
    // freeze even when the app is genuinely idle.
    Q_INVOKABLE quint32     beginBackgroundTask(const QString &category, const QString &reason);
    Q_INVOKABLE bool        endBackgroundTask(quint32 handle);
    Q_INVOKABLE QStringList currentCapabilities();

    // Shell-side AppLifecycleManager exposes registerApp(appId, root) /
    // unregisterApp(appId). MApp.qml's Component.onCompleted calls
    // AppLifecycleManager.registerApp() before knowing whether it's
    // running shell-side or runner-side, so the runner-side client has
    // to accept the call to keep the splash → revealReady chain alive.
    // No-op stubs: the runner sends a register signal over D-Bus via
    // requestRegister already (see MApp.qml), so duplicating that here
    // would be redundant. These exist purely so the QML call resolves
    // without "is not a function" and MApp.onCompleted runs to its end.
    Q_INVOKABLE void registerApp(const QString &appId, QObject *root = nullptr);
    Q_INVOKABLE void unregisterApp(const QString &appId);

  private:
    QDBusInterface m_iface;
};
