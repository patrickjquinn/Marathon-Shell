#pragma once

// clazy:excludeall=const-signal-or-slot
//
// Every object in this file is a D-Bus adaptor. Their property getters are
// deliberately public slots because that is what exports them as D-Bus
// methods -- a plain const member function is not callable over the bus.
// clazy sees "const getter marked as a slot" and reports 38 findings here,
// all of which are the intended design rather than a mistake.

#include <QDBusMessage>
#include <QHash>
#include <QObject>
#include <QDBusContext>

#include <QDBusVariant>
#include <QVariantList>
#include <QVariantMap>

namespace marathon {
    class Permissions;
}
class AppLaunchService;
class AppLifecycleManager;
class MarathonAppRegistry;
class ForegroundApp;
class SessionStore;

// The Marathon app (or "service:<unit>") a D-Bus caller's process belongs
// to, "" if none.

class IpcPermissionedService : public QObject, protected QDBusContext {
    Q_OBJECT

  public:
    IpcPermissionedService(marathon::Permissions *permissions, AppLaunchService *launchService,
                           QObject *parent = nullptr);

  protected:
    QString callerAppIdOrEmpty() const;
    bool    requirePermission(const QString &rateLimitKey, const QStringList &permissions);
    // As requirePermission, for the D-Bus name `sender` rather than this call's.
    bool    admit(const QString &sender, const QString &rateLimitKey,
                  const QStringList &permissions);

    marathon::Permissions *m_permissions   = nullptr;
    AppLaunchService          *m_launchService = nullptr;
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


class MarathonAppInstaller;

// The Store's and Settings' way to the shell's installer: store URLs and
// uninstalls, which their sandboxes can't do themselves.
class AppStoreObject : public IpcPermissionedService {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.AppStore1")

  public:
    AppStoreObject(MarathonAppInstaller *installer, marathon::Permissions *permissions,
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
