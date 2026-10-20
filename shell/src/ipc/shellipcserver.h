#pragma once

#include <QObject>

namespace marathon {
    class Permissions;
    class Audio;
}
class Modem;
class AppLaunchService;
class SettingsManager;
class AudioPolicyController;
class AudioRoutingManager;
class MarathonAppInstaller;
class AppLifecycleManager;
class MarathonAppRegistry;
class AmbienceService;
class WallpaperStore;
class ForegroundApp;
class SessionStore;

// The interfaces the shell's C++ still serves, on org.marathonos.Shell.Session;
// the Rust ones take org.marathonos.Shell.
class ShellIpcServer : public QObject {
    Q_OBJECT

  public:
    explicit ShellIpcServer(marathon::Permissions *permissions, Modem *telephony,
                            SettingsManager *settingsManager, marathon::Audio *audioManager,
                            AudioPolicyController *audioPolicy,
                            AudioRoutingManager   *audioRoutingManager,
                            AppLaunchService *appLaunchService, AppLifecycleManager *lifecycleManager,
                            MarathonAppRegistry *appRegistry, QObject *parent = nullptr);

    void setAmbienceService(AmbienceService *ambience) {
        m_ambience = ambience;
    }
    void setWallpaperStore(WallpaperStore *store) {
        m_wallpaperStore = store;
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
    Modem                 *m_telephony           = nullptr;
    SettingsManager       *m_settingsManager     = nullptr;
    AmbienceService       *m_ambience            = nullptr;
    WallpaperStore        *m_wallpaperStore      = nullptr;
    marathon::Audio       *m_audioManager        = nullptr;
    AudioPolicyController *m_audioPolicy         = nullptr;
    AudioRoutingManager   *m_audioRoutingManager = nullptr;
    MarathonAppInstaller  *m_appInstaller        = nullptr;
    ForegroundApp         *m_foregroundApp       = nullptr;
    SessionStore          *m_sessionStore        = nullptr;
    AppLaunchService      *m_appLaunchService    = nullptr;
    AppLifecycleManager   *m_lifecycleManager    = nullptr;
    MarathonAppRegistry   *m_appRegistry         = nullptr;
};
