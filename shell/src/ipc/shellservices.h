#pragma once

// clazy:excludeall=const-signal-or-slot
//
// Every object in this file is a D-Bus adaptor. Their property getters are
// deliberately public slots because that is what exports them as D-Bus
// methods -- a plain const member function is not callable over the bus.
// clazy sees "const getter marked as a slot" and reports 38 findings here,
// all of which are the intended design rather than a mistake.

#include <QHash>
#include <QSet>
#include <QObject>
#include <QDBusContext>
#include <QDBusUnixFileDescriptor>

#include <QDBusVariant>
#include <QVariantList>
#include <QVariantMap>

class MarathonPermissionManager;
class AppLaunchService;
class AppLifecycleManager;
class MarathonAppRegistry;

class Modem;
class SettingsManager;
class AmbienceService;
class WallpaperStore;
class Security;
class FactoryReset;
class Bluetooth;
namespace marathon {
    class Display;
    class Updates;
}
class Flashlight;
class Network;
class Modem;
class Power;
class ForegroundApp;
class SessionStore;
class AudioManagerCpp;
class AudioPolicyController;
class HapticManager;
class RotationManager;
class LocationManager;
class AlarmManagerCpp;

// The Marathon app (or "service:<unit>") a D-Bus caller's process belongs
// to, "" if none.
QString appIdForCallerPid(qint64 pid, AppLaunchService *als);

class IpcPermissionedService : public QObject, protected QDBusContext {
    Q_OBJECT

  public:
    IpcPermissionedService(MarathonPermissionManager *permissions, AppLaunchService *launchService,
                           QObject *parent = nullptr);

  protected:
    QString callerAppIdOrEmpty() const;
    bool    requirePermission(const QString &rateLimitKey, const QStringList &permissions);
    // As requirePermission, for the D-Bus name `sender` rather than this call's.
    bool    admit(const QString &sender, const QString &rateLimitKey,
                  const QStringList &permissions);

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
    // deckardd's prompt for an Android app, waydroid.<package>. Replies
    // once answered with answer allow, once, deny or cancel and precise.
    // Options: request, 16 hex digits; kind; once; accuracy; preciseDefault.
    QVariantMap PromptAndroid(const QString &appId, const QString &permission,
                              const QVariantMap &options);
    void        CancelAndroidPrompt(const QString &request);
    // A session daemon's gate for a caller of its own, marathon-rt's admit:
    // replies as requirePermission would to that caller.
    void        Admit(const QString &sender, const QString &area, const QStringList &permissions);

  signals:
    void PermissionGranted(const QString &appId, const QString &permission);
    void PermissionDenied(const QString &appId, const QString &permission);
    void PermissionRequested(const QString &appId, const QString &permission);

  private:
    QString       requireForeignPrompter();
    QSet<QString> m_waiting;
};

class AudioRoutingManager;

class TelephonyObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Telephony1")

  public:
    TelephonyObject(Modem *telephony, MarathonPermissionManager *permissions,
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

    Modem    *m_telephony    = nullptr;
    AudioRoutingManager *m_audioRouting = nullptr;
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
    void         SetSystemTime(qlonglong msecsSinceEpoch);

  signals:
    void PropertyChanged(const QString &name, const QDBusVariant &value);
    void DateTimeChangeFailed(const QString &reason);

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
    SecurityObject(Security *security, MarathonPermissionManager *permissions,
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
    // Erases the device at the next boot if `secret` is the owner's quick
    // PIN, or system password without one; EraseFailed says why not.
    void EraseAllContent(const QString &secret);

  signals:
    void StateChanged(const QVariantMap &state);
    void AuthenticationFailed(const QString &reason);
    void AuthenticationSuccess();
    void QuickPINChanged();
    void EraseFailed(const QString &reason);

  private:
    bool requireSystem() {
        return requirePermission("Security", {"system"});
    }
    QVariantMap      buildState() const;

    Security *m_security     = nullptr;
    FactoryReset    *m_factoryReset = nullptr;
};

class BluetoothObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Bluetooth1")

  public:
    BluetoothObject(Bluetooth *bt, MarathonPermissionManager *permissions,
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
    bool requireBluetooth() {
        return requirePermission("Bluetooth", {"bluetooth", "system"});
    }

    QVariantMap       buildState() const;
    QVariantList      buildDevices(bool pairedOnly) const;

    Bluetooth        *m_bt = nullptr;
};

class DisplayObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Display1")

  public:
    DisplayObject(marathon::Display *display, RotationManager *rotation, Flashlight *flashlight,
                  MarathonPermissionManager *permissions, AppLaunchService *launchService,
                  QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetAutoBrightness(bool enabled);
    void        SetRotationLock(bool locked);
    void        SetBrightness(double brightness);
    void        SetNightLightEnabled(bool enabled);
    void        SetNightLightTemperature(int temperature);
    void        SetNightLightSchedule(const QString &schedule);
    void        SetScreenState(bool on);
    // Wake() — no auth, just turns the panel on. Equivalent to a power
    // button tap. Useful for remote testing over SSH when there is no
    // physical button. Calls into marathon::Display::turnScreenOn().
    void Wake();

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Display", {"system"});
    }
    QVariantMap           buildState() const;

    marathon::Display              *m_display    = nullptr;
    RotationManager      *m_rotation   = nullptr;
    Flashlight *m_flashlight = nullptr;
};

class PowerObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Power1")

  public:
    PowerObject(Power *power, marathon::Display *display,
                MarathonPermissionManager *permissions, AppLaunchService *launchService,
                QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        SetPowerSaveMode(bool enabled);
    void        SetPowerProfile(const QString &profile);
    void        Suspend();
    void        Restart();
    void        Shutdown();
    // Turns the screen on as an alarm, call or notification does.
    bool Wake(const QString &reason);
    // Has a suspended device resume at epochSecs, in Doze as for background
    // work; one per app, replacing the last.
    bool ScheduleWake(qint64 epochSecs, const QString &reason);

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Power", {"system"});
    }
    QVariantMap            buildState() const;

    Power                       *m_power   = nullptr;
    marathon::Display           *m_display = nullptr;
    // ScheduleWake calls, answered once systemd has their timer.
    QHash<QString, QList<QDBusMessage>> m_pendingWakes;
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
    NetworkObject(Network *network, MarathonPermissionManager *permissions,
                  AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();

    void        EnableWifi();
    void        DisableWifi();
    void        ToggleWifi();
    void        ScanWifi();
    void        ConnectToNetwork(const QString &ssid, const QString &password);
    void        ConnectToHiddenNetwork(const QString &ssid, const QString &security,
                                       const QString &password);
    void        ForgetNetwork(const QString &ssid);
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

    Network *m_network = nullptr;
};

class ModemObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Modem1")

  public:
    ModemObject(Modem *modem, MarathonPermissionManager *permissions,
                AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        EnableData();
    void        DisableData();
    void        SetDataRoamingAllowed(bool allowed);
    void        SetAllowedModes(uint allowed);

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireNetwork() {
        return requirePermission("Modem", {"network", "system"});
    }
    QVariantMap      buildState() const;

    Modem *m_modem = nullptr;
};

class NavigationObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Navigation1")

  public:
    NavigationObject(AppLaunchService *launchService, QObject *parent = nullptr);
    void setForegroundApp(ForegroundApp *foreground);
    void setSessionStore(SessionStore *session) {
        m_session = session;
    }

  public slots:
    bool LaunchApp(const QString &appId);
    // Starts the app without bringing it to the front (Pilot's overlay).
    bool StartAppInBackground(const QString &appId);
    bool Navigate(const QString &uri);
    bool LaunchAppWithRoute(const QString &appId, const QString &route, const QString &paramsJson);
    // The app a process belongs to, "" if none (Pilot's on-screen context).
    QString AppIdForPid(uint pid);
    // The app in front, "" on the home screen, the switcher or the lock screen.
    QString GetForegroundApp();
    // Session services (Deckard) only. The app's window comes in front now,
    // or the next one it maps within 10 s; false while locked.
    bool    ExpectAppWindow(const QString &appId);
    // Session services only: the app's windows stay off cards and screenshots
    // until its card goes.
    void    SetAppWindowSecure(const QString &appId, bool secure);

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
    void DeepLinkRequested(const QString &appId, const QString &route, const QString &paramsJson);
    void ForegroundAppChanged(const QString &appId);

  private:
    QString           callerAppIdOrEmpty() const;
    AppLaunchService *m_launchService = nullptr;
    ForegroundApp    *m_foreground    = nullptr;
    SessionStore     *m_session       = nullptr;
    bool              requireService();
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

class SensorObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Sensor1")

  public:
    SensorObject(marathon::Display *sensors, MarathonPermissionManager *permissions,
                 AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    bool IsAvailable();
    bool ProximityNear();
    int  AmbientLight();

  signals:
    void ProximityChanged(bool near);
    void AmbientLightChanged(int lux);

  private:
    bool requireSensors() {
        return requirePermission("Sensor", {"sensors", "system"});
    }
    marathon::Display *m_sensors = nullptr;
};

class LocationObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Location1")

  public:
    LocationObject(LocationManager *location, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    bool        IsAvailable();
    bool        IsActive();
    void        Start();
    void        Stop();
    QVariantMap GetLocation();

  signals:
    void LocationChanged(const QVariantMap &location);
    void activeChanged(bool active);

  private:
    bool requireLocation() {
        return requirePermission("Location", {"location"});
    }
    QVariantMap      location() const;
    LocationManager *m_location = nullptr;
};

class AlarmObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Alarm1")

  public:
    AlarmObject(AlarmManagerCpp *alarms, MarathonPermissionManager *permissions,
                AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:

    QVariantList GetAlarms();
    QVariantList GetActiveAlarms();

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
    bool requireAlarms() {
        return requirePermission("Alarm", {"alarms", "system"});
    }
    AlarmManagerCpp *m_alarms = nullptr;
};


// Surfaces Updates over D-Bus so the Settings app (running in the
// app-runner process) can check for, install and reboot into OS updates.
class UpdatesObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Updates1")

  public:
    UpdatesObject(marathon::Updates *updates, MarathonPermissionManager *permissions,
                  AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QVariantMap GetState();
    void        CheckNow();
    void        Install();
    void        Cancel();
    void        Reboot();
    void        ScheduleRestart();
    void        SetAutoUpdate(bool on);

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    bool requireSystem() {
        return requirePermission("Updates", {"system"});
    }
    QVariantMap        buildState() const;

    marathon::Updates *m_updates = nullptr;
};

class MarathonAppInstaller;

// The Store's and Settings' way to the shell's installer: store URLs and
// uninstalls, which their sandboxes can't do themselves.
class AppStoreObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.AppStore1")

  public:
    AppStoreObject(MarathonAppInstaller *installer, MarathonPermissionManager *permissions,
                   AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    // Runs marathon-store-handler for a marathon-store:// URL. The Store's
    // own sandbox gives it a private home, so flatpak --user must run from
    // the shell's side of that boundary.
    void RunStoreUrl(const QString &url);
    // User installs are read-only inside every sandbox, so Settings removes
    // them through the shell. The outcome arrives as UninstallComplete or
    // UninstallFailed.
    bool CanUninstall(const QString &appId);
    void Uninstall(const QString &appId);

  signals:
    void UninstallComplete(const QString &appId);
    void UninstallFailed(const QString &appId, const QString &error);

  private:
    bool requireSystem() {
        return requirePermission("AppStore", {"system"});
    }
    MarathonAppInstaller *m_installer = nullptr;
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

// Public read: the ambience is what every app is drawn with.
class AmbienceObject : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Ambience1")

  public:
    explicit AmbienceObject(AmbienceService *ambience, QObject *parent = nullptr);

  public slots:
    QVariantMap GetAmbience();

  signals:
    void AmbienceChanged(const QVariantMap &ambience);

  private:
    AmbienceService *m_ambience = nullptr;
};

// Public read: the built-in wallpapers, for the Settings app's picker.
class WallpaperObject : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Wallpaper1")

  public:
    explicit WallpaperObject(WallpaperStore *store, QObject *parent = nullptr);

  public slots:
    QVariantList GetWallpapers();

  private:
    WallpaperStore *m_store = nullptr;
};
