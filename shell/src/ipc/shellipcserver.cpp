#include "shellipcserver.h"

#include "shellservices.h"

#include "marathon-shell-native/src/ipc.cxxqt.h"
#include "marathon-shell-native/src/audio.cxxqt.h"
#include "audiopolicycontroller.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

ShellIpcServer::ShellIpcServer(marathon::Permissions *permissions, marathon::Audio *audioManager,
                               AudioPolicyController *audioPolicy,
                               AppLaunchService      *appLaunchService,
                               AppLifecycleManager   *lifecycleManager,
                               MarathonAppRegistry *appRegistry, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_audioManager(audioManager)
    , m_audioPolicy(audioPolicy)
    , m_appLaunchService(appLaunchService)
    , m_lifecycleManager(lifecycleManager)
    , m_appRegistry(appRegistry) {}

bool ShellIpcServer::registerOnSessionBus() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[ShellIpcServer] Session bus not connected:" << bus.lastError().message();
        return false;
    }
    if (qEnvironmentVariableIntValue("MARATHON_TEST_TRUSTED") != 0) {
        qWarning() << "[ShellIpcServer] !!! MARATHON_TEST_TRUSTED is set -- IPC caller "
                      "verification is bypassed. Do NOT use in production.";
    }

    auto *navObj = new NavigationObject(m_appLaunchService, this);
    if (m_foregroundApp)
        navObj->setForegroundApp(m_foregroundApp);
    navObj->setSessionStore(m_sessionStore);

    const auto all = QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals;
    bool       ok  = true;
    ok &= bus.registerObject(
        "/org/marathonos/Shell/Audio",
        new AudioObject(m_audioManager, m_audioPolicy, m_permissions, m_appLaunchService, this),
        all);
    ok &= bus.registerObject("/org/marathonos/Shell/Navigation", navObj, all);
    ok &= bus.registerObject(
        "/org/marathonos/Shell/AppStore",
        new AppStoreObject(m_appInstaller, m_permissions, m_appLaunchService, this), all);
    ok &= bus.registerObject(
        "/org/marathonos/Shell/AppLifecycle",
        new AppLifecycleObject(m_lifecycleManager, m_appRegistry, m_appLaunchService, this), all);
    ok &= bus.registerService("org.marathonos.Shell.Session");
    if (!ok) {
        qWarning() << "[ShellIpcServer] Failed to register the session's DBus API:"
                   << bus.lastError().message();
        return false;
    }
    marathon::ipc::own_name();
    return true;
}
