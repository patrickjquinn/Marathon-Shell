#pragma once

#include <QHash>
#include <QObject>
#include <QDBusContext>
#include <QDBusVariant>
#include <QVariantList>
#include <QVariantMap>

class MarathonPermissionManager;
class AppLaunchService;
class AppLifecycleManager;
class MarathonAppRegistry;

class ContactsManager;
class CallHistoryManager;
class TelephonyService;
class SMSService;
class MediaLibraryManager;
class SettingsManager;
class SecurityManager;
class BluetoothManager;
class DisplayManagerCpp;
class NetworkManagerCpp;
class PowerManagerCpp;
class AudioManagerCpp;
class AudioPolicyController;
class HapticManager;
class SensorManagerCpp;
class LocationManager;
class AlarmManagerCpp;

class IpcPermissionedService : public QObject, protected QDBusContext {
    Q_OBJECT

  public:
    IpcPermissionedService(MarathonPermissionManager *permissions, AppLaunchService *launchService,
                           QObject *parent = nullptr);

  protected:
    QString callerAppIdOrEmpty() const;
    bool    requirePermission(const QString &rateLimitKey, const QStringList &permissions);

    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class PermissionsObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public:
    PermissionsObject(MarathonPermissionManager *permissions, AppLaunchService *launchService,
                      QObject *parent = nullptr);

  public slots:
    bool HasPermission(const QString &appId, const QString &permission);
    void RequestPermission(const QString &appId, const QString &permission);
    void SetPermission(const QString &appId, const QString &permission, bool granted,
                       bool remember = true);

  signals:
    void PermissionGranted(const QString &appId, const QString &permission);
    void PermissionDenied(const QString &appId, const QString &permission);
    void PermissionRequested(const QString &appId, const QString &permission);
};

class ContactsObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Contacts1")

  public:
    ContactsObject(ContactsManager *contacts, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantList GetContacts();
    QVariantMap  GetContact(int id);
    QVariantMap  GetContactByNumber(const QString &phoneNumber);
    QVariantList SearchContacts(const QString &query);
    void         AddContact(const QString &name, const QString &phone, const QString &email);
    void         UpdateContact(int id, const QVariantMap &data);
    void         DeleteContact(int id);

  signals:
    void ContactsChanged();
    void ContactAdded(int id);
    void ContactUpdated(int id);
    void ContactDeleted(int id);

  private:
    bool requireContacts() {
        return requirePermission("Contacts", {"contacts"});
    }

    ContactsManager *m_contacts = nullptr;
};

class CallHistoryObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.CallHistory1")

  public:
    CallHistoryObject(CallHistoryManager *callHistory, MarathonPermissionManager *permissions,
                      AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantList GetHistory();
    QVariantMap  GetCallById(int id);
    QVariantList GetCallsByNumber(const QString &number);
    void AddCall(const QString &number, const QString &type, qint64 timestamp, int duration);
    void DeleteCall(int id);
    void ClearHistory();

  signals:
    void HistoryChanged();
    void CallAdded(int id);

  private:
    bool requirePhone() {
        return requirePermission("CallHistory", {"telephony", "phone"});
    }

    CallHistoryManager *m_callHistory = nullptr;
};

class AudioRoutingManager;

class TelephonyObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Telephony1")

  public:
    TelephonyObject(TelephonyService *telephony, MarathonPermissionManager *permissions,
                    AppLaunchService *launchService, AudioRoutingManager *audioRouting,
                    QObject *parent = nullptr);

  public slots:
    QString CallState() const;
    bool    HasModem() const;
    QString ActiveNumber() const;
    void    Dial(const QString &number);
    void    Answer();
    void    Hangup();
    void    SendDTMF(const QString &digit);

    void    SetSpeakerphone(bool on);
    void    SetCallMuted(bool muted);
    bool    IsSpeakerphoneOn() const;
    bool    IsCallMuted() const;

    void    SimulateIncomingCall(const QString &number);
    void    SimulateCallStateChange(const QString &state);

  signals:
    void CallStateChanged(const QString &state);
    void IncomingCall(const QString &number);
    void CallFailed(const QString &reason);
    void ModemChanged(bool hasModem);
    void ActiveNumberChanged(const QString &number);

  private:
    bool requirePhone() {
        return requirePermission("Telephony", {"telephony", "phone"});
    }

    TelephonyService    *m_telephony    = nullptr;
    AudioRoutingManager *m_audioRouting = nullptr;
};

class SmsObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Sms1")

  public:
    SmsObject(SMSService *sms, MarathonPermissionManager *permissions,
              AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantList GetConversations();
    QVariantList GetMessages(const QString &conversationId);
    void         SendMessage(const QString &recipient, const QString &text);
    void         DeleteConversation(const QString &conversationId);
    void         MarkAsRead(const QString &conversationId);
    QString      GenerateConversationId(const QString &number);

    void         SimulateIncomingSMS(const QString &sender, const QString &message);

  signals:
    void MessageReceived(const QString &sender, const QString &text, qint64 timestamp);
    void MessageSent(const QString &recipient, qint64 timestamp);
    void SendFailed(const QString &recipient, const QString &reason);
    void ConversationsChanged();

  private:
    bool requireSms() {
        return requirePermission("Sms", {"sms", "phone"});
    }

    SMSService *m_sms = nullptr;
};

class MediaLibraryObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.MediaLibrary1")

  public:
    MediaLibraryObject(MediaLibraryManager *media, MarathonPermissionManager *permissions,
                       AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantList Albums();
    bool         IsScanning() const;
    int          PhotoCount() const;
    int          VideoCount() const;
    int          ScanProgress() const;

    void         ScanLibrary();
    void         ScanLibraryAsync();
    QVariantList GetPhotos(const QString &albumId);
    QVariantList GetAllPhotos();
    QVariantList GetVideos();
    QString      GenerateThumbnail(const QString &filePath);
    void         DeleteMedia(int mediaId);

  signals:
    void AlbumsChanged();
    void ScanningChanged(bool scanning);
    void ScanComplete(int photoCount, int videoCount);
    void NewMediaAdded(const QString &path);
    void LibraryChanged();
    void ScanProgressChanged(int progress);

  private:
    bool requireStorage() {
        return requirePermission("MediaLibrary", {"storage"});
    }

    MediaLibraryManager *m_media = nullptr;
};

class SettingsObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Settings1")

  public:
    SettingsObject(SettingsManager *settings, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap  GetState();
    void         SetProperty(const QString &name, const QDBusVariant &value);

    QStringList  AvailableRingtones();
    QStringList  AvailableNotificationSounds();
    QStringList  AvailableAlarmSounds();
    QStringList  ScreenTimeoutOptions();
    int          ScreenTimeoutValue(const QString &option);
    QString      FormatSoundName(const QString &path);
    QString      AssetUrl(const QString &relativePath);

    QDBusVariant Get(const QString &key, const QDBusVariant &defaultValue = QDBusVariant());
    void         Set(const QString &key, const QDBusVariant &value);
    void         Sync();

  signals:
    void PropertyChanged(const QString &name, const QDBusVariant &value);

  private:
    bool requireSystem() {
        return requirePermission("Settings", {"system"});
    }
    bool requireStorage() {
        return requirePermission("Settings.Storage", {"storage"});
    }
    bool             isAppScopedKey(const QString &key) const;

    SettingsManager *m_settings = nullptr;
};

class SecurityObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Security1")

  public:
    SecurityObject(SecurityManager *security, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetQuickPIN(const QString &pin, const QString &systemPassword);
    void        RemoveQuickPIN(const QString &systemPassword);
    void        AuthenticatePassword(const QString &password);
    void        AuthenticateQuickPIN(const QString &pin);
    void        AuthenticateBiometric(int type);
    void        CancelAuthentication();
    void        ResetLockout();
    bool        IsBiometricEnrolled(int type);
    QString     CurrentUsername();

  signals:
    void StateChanged(const QVariantMap &state);
    void AuthenticationFailed(const QString &reason);
    void AuthenticationSuccess();
    void QuickPINChanged();

  private:
    bool requireSystem() {
        return requirePermission("Security", {"system"});
    }
    QVariantMap      buildState() const;

    SecurityManager *m_security = nullptr;
};

class BluetoothObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Bluetooth1")

  public:
    BluetoothObject(BluetoothManager *bt, MarathonPermissionManager *permissions,
                    AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetEnabled(bool enabled);
    void        StartScan();
    void        StopScan();
    void        ConnectDevice(const QString &address);
    void        DisconnectDevice(const QString &address);
    void        PairDevice(const QString &address, const QString &pin = QString());
    void        UnpairDevice(const QString &address);
    void        ConfirmPairing(const QString &address, bool confirmed);
    void        CancelPairing(const QString &address);

  signals:
    void StateChanged(const QVariantMap &state);
    void PairingFailed(const QString &address, const QString &error);
    void PairingSucceeded(const QString &address);
    void PinRequested(const QString &address, const QString &deviceName);
    void PasskeyRequested(const QString &address, const QString &deviceName);
    void PasskeyConfirmation(const QString &address, const QString &deviceName, quint32 passkey);

  private:
    bool requireSystem() {
        return requirePermission("Bluetooth", {"system"});
    }

    QVariantMap       buildState() const;
    QVariantList      buildDevices(bool pairedOnly) const;

    BluetoothManager *m_bt = nullptr;
};

class DisplayObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Display1")

  public:
    DisplayObject(DisplayManagerCpp *display, MarathonPermissionManager *permissions,
                  AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetAutoBrightness(bool enabled);
    void        SetRotationLock(bool locked);
    void        SetScreenTimeout(int seconds);
    void        SetBrightness(double brightness);
    void        SetNightLightEnabled(bool enabled);
    void        SetNightLightTemperature(int temperature);
    void        SetNightLightSchedule(const QString &schedule);
    void        SetScreenState(bool on);
    // Wake() — no auth, just turns the panel on. Equivalent to a power
    // button tap. Useful for remote testing over SSH when there is no
    // physical button. Calls into DisplayManager::setScreenState(true).
    void Wake();

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Display", {"system"});
    }
    QVariantMap        buildState() const;

    DisplayManagerCpp *m_display = nullptr;
};

class PowerObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Power1")

  public:
    PowerObject(PowerManagerCpp *power, MarathonPermissionManager *permissions,
                AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetPowerSaveMode(bool enabled);
    void        SetPowerProfile(const QString &profile);
    void        Suspend();
    void        Restart();
    void        Shutdown();

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Power", {"system"});
    }
    QVariantMap      buildState() const;

    PowerManagerCpp *m_power = nullptr;
};

class AudioObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Audio1")

  public:
    AudioObject(AudioManagerCpp *audio, AudioPolicyController *policy,
                MarathonPermissionManager *permissions, AppLaunchService *launchService,
                QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetVolume(double volume);
    void        SetMuted(bool muted);
    void        SetStreamVolume(int streamId, double volume);
    void        SetStreamMuted(int streamId, bool muted);
    void        RefreshStreams();

    void        SetDoNotDisturb(bool enabled);
    void        SetAudioProfile(const QString &profile);

    void        PlayRingtone();
    void        StopRingtone();
    void        PlayNotificationSound();
    void        PlayAlarmSound();
    void        StopAlarmSound();
    void        PreviewSound(const QString &soundPath);
    void        VibratePattern(const QVariantList &pattern);

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Audio", {"system"});
    }
    QVariantMap            buildState() const;

    AudioManagerCpp       *m_audio  = nullptr;
    AudioPolicyController *m_policy = nullptr;
};

class NetworkObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Network1")

  public:
    NetworkObject(NetworkManagerCpp *network, MarathonPermissionManager *permissions,
                  AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();

    void        EnableWifi();
    void        DisableWifi();
    void        ToggleWifi();
    void        ScanWifi();
    void        ConnectToNetwork(const QString &ssid, const QString &password);
    void        DisconnectWifi();

    void        SetAirplaneMode(bool enabled);

    void        CreateHotspot(const QString &ssid, const QString &password);
    void        StopHotspot();
    bool        IsHotspotActive() const;

  signals:
    void StateChanged(const QVariantMap &state);
    void NetworkError(const QString &message);
    void ConnectionSuccess();
    void ConnectionFailed(const QString &message);

  private:
    bool requireNetwork() {
        return requirePermission("Network", {"network", "system"});
    }
    QVariantMap        buildState() const;

    NetworkManagerCpp *m_network = nullptr;
};

class NavigationObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Navigation1")

  public:
    NavigationObject(AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    bool LaunchApp(const QString &appId);
    bool Navigate(const QString &uri);
    bool LaunchAppWithRoute(const QString &appId, const QString &route, const QString &paramsJson);

    // Quick Settings shade control (marathon CLI `qs` verb). Lets a dev host
    // pull the shade over D-Bus, since top-edge touch injection never reaches
    // the shell's statusBarDragArea. No caller auth — the shade exposes only
    // system toggles the lock screen already gates, same rationale as LaunchApp.
    bool ShowQuickSettings();
    bool HideQuickSettings();
    bool ToggleQuickSettings();

  signals:
    void AppLaunched(const QString &appId);
    void NavigationFailed(const QString &uri, const QString &error);

  private:
    QString           callerAppIdOrEmpty() const;
    AppLaunchService *m_launchService = nullptr;
};

class HapticObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Haptic1")

  public:
    HapticObject(HapticManager *haptic, AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    bool IsAvailable() const;
    void Light();
    void Medium();
    void Heavy();
    void Vibrate(int duration);
    void VibratePattern(const QVariantList &pattern);
    void Stop();

  private:
    HapticManager    *m_haptic        = nullptr;
    AppLaunchService *m_launchService = nullptr;
};

class SensorObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Sensor1")

  public:
    SensorObject(SensorManagerCpp *sensors, AppLaunchService *launchService,
                 QObject *parent = nullptr);

  public slots:
    bool IsAvailable() const;
    bool ProximityNear() const;
    int  AmbientLight() const;

  signals:
    void ProximityChanged(bool near);
    void AmbientLightChanged(int lux);

  private:
    SensorManagerCpp *m_sensors       = nullptr;
    AppLaunchService *m_launchService = nullptr;
};

class LocationObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Location1")

  public:
    LocationObject(LocationManager *location, AppLaunchService *launchService,
                   QObject *parent = nullptr);

  public slots:
    bool        IsAvailable() const;
    bool        IsActive() const;
    void        Start();
    void        Stop();
    QVariantMap GetLocation() const;

  signals:
    void LocationChanged(const QVariantMap &location);
    void activeChanged(bool active);

  private:
    LocationManager  *m_location      = nullptr;
    AppLaunchService *m_launchService = nullptr;
};

class AlarmObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Alarm1")

  public:
    AlarmObject(AlarmManagerCpp *alarms, AppLaunchService *launchService,
                QObject *parent = nullptr);

  public slots:

    QVariantList GetAlarms() const;
    QVariantList GetActiveAlarms() const;

    QString      CreateAlarm(const QString &time, const QString &label, const QList<int> &repeat,
                             const QVariantMap &options);
    bool         UpdateAlarm(const QString &id, const QVariantMap &updates);
    bool         DeleteAlarm(const QString &id);
    bool         EnableAlarm(const QString &id);
    bool         DisableAlarm(const QString &id);
    bool         SnoozeAlarm(const QString &id);
    bool         DismissAlarm(const QString &id);
    void         StopAll();
    void         TriggerAlarmNow(const QString &label);

  signals:
    void AlarmsChanged();
    void ActiveAlarmsChanged();
    void AlarmTriggered(const QString &id, const QString &label);
    void AlarmDismissed(const QString &id);
    void AlarmSnoozed(const QString &id, int minutes);

  private:
    AlarmManagerCpp  *m_alarms        = nullptr;
    AppLaunchService *m_launchService = nullptr;
};

class UpdateService;
class DavSyncEngine;

// Surfaces UpdateService over D-Bus so the Settings app (running in the
// app-runner process) can show a "Software updates" tile that reflects the
// shell's polling state.
class UpdatesObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Updates1")

  public:
    UpdatesObject(UpdateService *updates, MarathonPermissionManager *permissions,
                  AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        CheckNow();
    void        OpenInBrowser();
    void        SetChannel(const QString &channel);

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Updates", {"system"});
    }
    QVariantMap    buildState() const;

    UpdateService *m_updates = nullptr;
};

// Surfaces DavSyncEngine: account add/remove/list + sync trigger. Settings
// app needs this for the "Accounts → Add CardDAV" flow.
class DavObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Dav1")

  public:
    DavObject(DavSyncEngine *engine, MarathonPermissionManager *permissions,
              AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantList ListAccounts();
    QString AddAccount(const QString &displayName, const QString &baseUrl, const QString &username,
                       const QString &secret, const QString &authKind);
    bool    RemoveAccount(const QString &id);
    void    EnableAccount(const QString &id, bool enabled);
    void    SyncNow();
    QVariantMap GetState();

  signals:
    void AccountsChanged();
    void SyncFinished(const QString &accountId);
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Dav", {"system"});
    }

    DavSyncEngine *m_engine = nullptr;
};

class MarathonAppStoreService;

// Surfaces MarathonAppStoreService over D-Bus so the Store app (running
// in the app-runner process) can query the catalog and ask the shell
// to download apps. Catalog reads gate on the lighter "system" perm;
// downloads gate on "system" too because they trigger MarathonAppInstaller
// in the shell with elevated rights.
class AppStoreObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.AppStore1")

  public:
    AppStoreObject(MarathonAppStoreService *appStore, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap  GetState();
    void         RefreshCatalog();
    QVariantList SearchApps(const QString &query);
    QVariantMap  GetApp(const QString &appId);
    QVariantList GetFeaturedApps();
    QVariantList GetAppsByCategory(const QString &category);
    QVariantList GetAvailableUpdates();
    void         CheckForUpdates();
    void         DownloadApp(const QString &appId);
    void         CancelDownload(const QString &appId);

  signals:
    void StateChanged(const QVariantMap &state);
    void CatalogRefreshed();
    void DownloadProgress(const QString &appId, qint64 bytesReceived, qint64 bytesTotal);
    void DownloadComplete(const QString &appId, const QString &packagePath);
    void DownloadFailed(const QString &appId, const QString &error);

  private:
    bool requireSystem() {
        return requirePermission("AppStore", {"system"});
    }
    QVariantMap              buildState() const;

    MarathonAppStoreService *m_appStore = nullptr;
};

// Lets apps (via marathon-app-runner) declare active background work like
// turn-by-turn navigation, recording, large downloads, periodic sync. The
// MPRIS2 + Telephony observers cover audio playback and active calls
// automatically; everything else needs the app to claim explicitly so the
// shell knows not to freeze it.
//
// Caller is identified by DBus PID resolution (the same trusted path the
// rest of shellservices uses); the manifest's `backgroundCapabilities`
// gates which categories are accepted.
class AppLifecycleObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.AppLifecycle1")

  public:
    AppLifecycleObject(AppLifecycleManager *lifecycle, MarathonAppRegistry *appRegistry,
                       AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    // Returns a non-zero handle on success, 0 on rejection (unknown
    // caller, category not declared in manifest, lifecycle unavailable).
    // Multiple Begin calls for the same category from one app are
    // refcounted — the capability lifts only after the matching number of
    // End calls.
    quint32     BeginBackgroundTask(const QString &category, const QString &reason);
    bool        EndBackgroundTask(quint32 handle);
    QStringList GetMyCapabilities();

  private:
    struct ActiveTask {
        QString appId;
        QString category;
    };

    AppLifecycleManager       *m_lifecycle     = nullptr;
    MarathonAppRegistry       *m_appRegistry   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
    quint32                    m_nextHandle    = 1;
    QHash<quint32, ActiveTask> m_handles;
};
