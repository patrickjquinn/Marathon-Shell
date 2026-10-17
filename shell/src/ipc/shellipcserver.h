#pragma once

#include <QObject>

class QDBusConnection;

class MarathonPermissionManager;
class ContactsManager;
class CallHistoryManager;
class TelephonyService;
class SMSService;
class AppLaunchService;
class MediaLibraryManager;
class SettingsManager;
class BluetoothManager;
class DisplayManagerCpp;
class NetworkManagerCpp;
class PowerManagerCpp;
class PowerPolicyController;
class AudioManagerCpp;
class AudioPolicyController;
class HapticManager;
class SecurityManager;
class SensorManagerCpp;
class LocationManager;
class AlarmManagerCpp;
class AudioRoutingManager;
class UpdateService;
class DavSyncEngine;
class MarathonAppStoreService;
class MarathonAppInstaller;
class AppLifecycleManager;
class MarathonAppRegistry;

class AmbienceService;
class WallpaperStore;
class ModemManagerCpp;
class FlashlightManagerCpp;

class ShellIpcServer : public QObject {
    Q_OBJECT

  public:
    explicit ShellIpcServer(MarathonPermissionManager *permissions, ContactsManager *contacts,
                            CallHistoryManager *callHistory, TelephonyService *telephony,
                            SMSService *sms, MediaLibraryManager *mediaLibrary,
                            SettingsManager *settingsManager, BluetoothManager *bluetoothManager,
                            DisplayManagerCpp *displayManager, PowerManagerCpp *powerManager,
                            AudioManagerCpp *audioManager, AudioPolicyController *audioPolicy,
                            NetworkManagerCpp *networkManager, HapticManager *hapticManager,
                            SecurityManager *securityManager, SensorManagerCpp *sensorManager,
                            LocationManager *locationManager, AlarmManagerCpp *alarmManager,
                            AudioRoutingManager *audioRoutingManager, UpdateService *updateService,
                            DavSyncEngine *davSyncEngine, MarathonAppStoreService *appStoreService,
                            AppLaunchService    *appLaunchService,
                            AppLifecycleManager *lifecycleManager, MarathonAppRegistry *appRegistry,
                            QObject *parent = nullptr);

    void setAmbienceService(AmbienceService *ambience) {
        m_ambience = ambience;
    }
    void setWallpaperStore(WallpaperStore *store) {
        m_wallpaperStore = store;
    }
    void setModemManager(ModemManagerCpp *modem) {
        m_modemManager = modem;
    }
    void setFlashlightManager(FlashlightManagerCpp *flashlight) {
        m_flashlightManager = flashlight;
    }
    void setPowerPolicy(PowerPolicyController *policy) {
        m_powerPolicy = policy;
    }
    void setAppInstaller(MarathonAppInstaller *installer) {
        m_appInstaller = installer;
    }
    bool registerOnSessionBus();

  private:
    MarathonPermissionManager *m_permissions         = nullptr;
    ContactsManager           *m_contacts            = nullptr;
    CallHistoryManager        *m_callHistory         = nullptr;
    TelephonyService          *m_telephony           = nullptr;
    SMSService                *m_sms                 = nullptr;
    MediaLibraryManager       *m_mediaLibrary        = nullptr;
    SettingsManager           *m_settingsManager     = nullptr;
    AmbienceService           *m_ambience            = nullptr;
    WallpaperStore            *m_wallpaperStore      = nullptr;
    ModemManagerCpp           *m_modemManager        = nullptr;
    FlashlightManagerCpp      *m_flashlightManager   = nullptr;
    BluetoothManager          *m_bluetoothManager    = nullptr;
    DisplayManagerCpp         *m_displayManager      = nullptr;
    PowerManagerCpp           *m_powerManager        = nullptr;
    PowerPolicyController     *m_powerPolicy         = nullptr;
    AudioManagerCpp           *m_audioManager        = nullptr;
    AudioPolicyController     *m_audioPolicy         = nullptr;
    NetworkManagerCpp         *m_networkManager      = nullptr;
    HapticManager             *m_hapticManager       = nullptr;
    SecurityManager           *m_securityManager     = nullptr;
    SensorManagerCpp          *m_sensorManager       = nullptr;
    LocationManager           *m_locationManager     = nullptr;
    AlarmManagerCpp           *m_alarmManager        = nullptr;
    AudioRoutingManager       *m_audioRoutingManager = nullptr;
    UpdateService             *m_updateService       = nullptr;
    DavSyncEngine             *m_davSyncEngine       = nullptr;
    MarathonAppStoreService   *m_appStoreService     = nullptr;
    MarathonAppInstaller      *m_appInstaller        = nullptr;
    AppLaunchService          *m_appLaunchService    = nullptr;
    AppLifecycleManager       *m_lifecycleManager    = nullptr;
    MarathonAppRegistry       *m_appRegistry         = nullptr;
};
