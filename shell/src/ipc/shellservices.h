#pragma once

#include <QObject>
#include <QDBusContext>
#include <QDBusVariant>
#include <QVariantList>
#include <QVariantMap>

class MarathonPermissionManager;
class AppLaunchService;

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

class PermissionsObject : public QObject, protected QDBusContext {
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

  private:
    QString                    callerAppIdOrEmpty() const;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class ContactsObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireContacts();

    ContactsManager           *m_contacts      = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class CallHistoryObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requirePhone();

    CallHistoryManager        *m_callHistory   = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class TelephonyObject : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Telephony1")

  public:
    TelephonyObject(TelephonyService *telephony, MarathonPermissionManager *permissions,
                    AppLaunchService *launchService, QObject *parent = nullptr);

  public slots:
    QString CallState() const;
    bool    HasModem() const;
    QString ActiveNumber() const;
    void    Dial(const QString &number);
    void    Answer();
    void    Hangup();
    void    SendDTMF(const QString &digit);

    void    SimulateIncomingCall(const QString &number);
    void    SimulateCallStateChange(const QString &state);

  signals:
    void CallStateChanged(const QString &state);
    void IncomingCall(const QString &number);
    void CallFailed(const QString &reason);
    void ModemChanged(bool hasModem);
    void ActiveNumberChanged(const QString &number);

  private:
    QString                    callerAppIdOrEmpty() const;
    bool                       requirePhone();

    TelephonyService          *m_telephony     = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class SmsObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSms();

    SMSService                *m_sms           = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class MediaLibraryObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireStorage();

    MediaLibraryManager       *m_media         = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class SettingsObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();
    bool                       requireStorage();
    bool                       isAppScopedKey(const QString &key) const;

    SettingsManager           *m_settings      = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class SecurityObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();
    QVariantMap                buildState() const;

    SecurityManager           *m_security      = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class BluetoothObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();

    QVariantMap                buildState() const;
    QVariantList               buildDevices(bool pairedOnly) const;

    BluetoothManager          *m_bt            = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class DisplayObject : public QObject, protected QDBusContext {
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

  signals:
    void StateChanged(const QVariantMap &state);

  private:
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();
    QVariantMap                buildState() const;

    DisplayManagerCpp         *m_display       = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class PowerObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();
    QVariantMap                buildState() const;

    PowerManagerCpp           *m_power         = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class AudioObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireSystem();
    QVariantMap                buildState() const;

    AudioManagerCpp           *m_audio         = nullptr;
    AudioPolicyController     *m_policy        = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
};

class NetworkObject : public QObject, protected QDBusContext {
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
    QString                    callerAppIdOrEmpty() const;
    bool                       requireNetwork();
    QVariantMap                buildState() const;

    NetworkManagerCpp         *m_network       = nullptr;
    MarathonPermissionManager *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
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
