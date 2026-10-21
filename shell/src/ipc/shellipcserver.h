#pragma once

#include <QObject>

namespace marathon {
    class Permissions;
}
class AppLaunchService;
class MarathonAppInstaller;
class AppLifecycleManager;
class MarathonAppRegistry;
class ForegroundApp;
class SessionStore;

// The interfaces the shell's C++ still serves, on org.marathonos.Shell.Session;
// the Rust ones take org.marathonos.Shell.
class ShellIpcServer : public QObject {
    Q_OBJECT

  public:
    explicit ShellIpcServer(marathon::Permissions *permissions,
                            AppLaunchService *appLaunchService, AppLifecycleManager *lifecycleManager,
                            MarathonAppRegistry *appRegistry, QObject *parent = nullptr);

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
    MarathonAppInstaller  *m_appInstaller        = nullptr;
    ForegroundApp         *m_foregroundApp       = nullptr;
    SessionStore          *m_sessionStore        = nullptr;
    AppLaunchService      *m_appLaunchService    = nullptr;
    AppLifecycleManager   *m_lifecycleManager    = nullptr;
    MarathonAppRegistry   *m_appRegistry         = nullptr;
};
