#pragma once

#include <QObject>

class QDBusConnection;

namespace marathon {
    class Permissions;
}
class Modem;
class AppLaunchService;
class SettingsManager;
class Bluetooth;
namespace marathon {
    class Audio;
    class Display;
    class Updates;
}
class Network;
class Power;
class AudioPolicyController;
class Haptics;
class Security;
class RotationManager;
class Location;
class Alarms;
class AudioRoutingManager;
class MarathonAppInstaller;
class AppLifecycleManager;
class MarathonAppRegistry;

class AmbienceService;
class WallpaperStore;
class ForegroundApp;
class SessionStore;
class Modem;
class Flashlight;

class ShellIpcServer : public QObject {
    Q_OBJECT

  public:
    explicit ShellIpcServer(marathon::Permissions *permissions,
                            Modem *telephony,
                            SettingsManager *settingsManager, Bluetooth *bluetoothManager,
                            marathon::Display *display, Power *powerManager,
                            marathon::Audio *audioManager, AudioPolicyController *audioPolicy,
                            Network *networkManager, Haptics *hapticManager,
                            Security *securityManager, RotationManager *rotationManager,
                            Location *locationManager, Alarms *alarmManager,
                            AudioRoutingManager *audioRoutingManager, marathon::Updates *updateService,
                            AppLaunchService    *appLaunchService,
                            AppLifecycleManager *lifecycleManager, MarathonAppRegistry *appRegistry,
                            QObject *parent = nullptr);

    void setAmbienceService(AmbienceService *ambience) {
        m_ambience = ambience;
    }
    void setWallpaperStore(WallpaperStore *store) {
        m_wallpaperStore = store;
    }
    void setModemManager(Modem *modem) {
        m_modemManager = modem;
    }
    void setFlashlightManager(Flashlight *flashlight) {
        m_flashlightManager = flashlight;
    }
    void setAppInstaller(MarathonAppInstaller *installer) {
        m_appInstaller = installer;
    }
    void setForegroundApp(ForegroundApp *foreground) {
        m_foregroundApp = foreground;
    }
    void setSessionStore(SessionStore *session) {
        m_sessionStore = session;
    }
    bool registerOnSessionBus();

  private:
    marathon::Permissions *m_permissions         = nullptr;
    Modem          *m_telephony           = nullptr;
    SettingsManager           *m_settingsManager     = nullptr;
    AmbienceService           *m_ambience            = nullptr;
    WallpaperStore            *m_wallpaperStore      = nullptr;
    Modem           *m_modemManager        = nullptr;
    Flashlight                *m_flashlightManager   = nullptr;
    Bluetooth                 *m_bluetoothManager    = nullptr;
    marathon::Display                   *m_display             = nullptr;
    Power           *m_powerManager        = nullptr;
    marathon::Audio           *m_audioManager        = nullptr;
    AudioPolicyController     *m_audioPolicy         = nullptr;
    Network         *m_networkManager      = nullptr;
    Haptics                   *m_hapticManager       = nullptr;
    Security           *m_securityManager     = nullptr;
    RotationManager           *m_rotationManager     = nullptr;
    Location                  *m_locationManager     = nullptr;
    Alarms                    *m_alarmManager        = nullptr;
    AudioRoutingManager       *m_audioRoutingManager = nullptr;
    marathon::Updates         *m_updateService       = nullptr;
    MarathonAppInstaller      *m_appInstaller        = nullptr;
    ForegroundApp             *m_foregroundApp       = nullptr;
    SessionStore              *m_sessionStore        = nullptr;
    AppLaunchService          *m_appLaunchService    = nullptr;
    AppLifecycleManager       *m_lifecycleManager    = nullptr;
    MarathonAppRegistry       *m_appRegistry         = nullptr;
};
