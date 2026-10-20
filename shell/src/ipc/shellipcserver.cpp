#include "shellipcserver.h"

#include "shellservices.h"

#include "marathonpermissionmanager.h"

#include "marathon-shell-native/src/modem.cxxqt.h"
#include "settingsmanager.h"
#include "marathon-shell-native/src/bluetooth.cxxqt.h"
#include "marathon-shell-native/src/network.cxxqt.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include "audiomanagercpp.h"
#include "audiopolicycontroller.h"
#include "marathon-shell-native/src/haptics.cxxqt.h"
#include "locationmanager.h"
#include "alarmmanagercpp.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

ShellIpcServer::ShellIpcServer(MarathonPermissionManager *permissions,
                               Modem *telephony,
                               SettingsManager *settingsManager, Bluetooth *bluetoothManager,
                               marathon::Display *display, Power *powerManager,
                               AudioManagerCpp *audioManager, AudioPolicyController *audioPolicy,
                               Network *networkManager, Haptics *hapticManager,
                               Security *securityManager, RotationManager *rotationManager,
                               LocationManager *locationManager, AlarmManagerCpp *alarmManager,
                               AudioRoutingManager *audioRoutingManager,
                               marathon::Updates *updateService,
                               AppLaunchService        *appLaunchService,
                               AppLifecycleManager     *lifecycleManager,
                               MarathonAppRegistry *appRegistry, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_telephony(telephony)
    , m_settingsManager(settingsManager)
    , m_bluetoothManager(bluetoothManager)
    , m_display(display)
    , m_powerManager(powerManager)
    , m_audioManager(audioManager)
    , m_audioPolicy(audioPolicy)
    , m_networkManager(networkManager)
    , m_hapticManager(hapticManager)
    , m_securityManager(securityManager)
    , m_rotationManager(rotationManager)
    , m_locationManager(locationManager)
    , m_alarmManager(alarmManager)
    , m_audioRoutingManager(audioRoutingManager)
    , m_updateService(updateService)
    , m_appLaunchService(appLaunchService)
    , m_lifecycleManager(lifecycleManager)
    , m_appRegistry(appRegistry) {}

bool ShellIpcServer::registerOnSessionBus() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[ShellIpcServer] Session bus not connected:" << bus.lastError().message();
        return false;
    }

    qInfo() << "[ShellIpcServer] Registering DBus service org.marathonos.Shell…";
    if (qEnvironmentVariableIntValue("MARATHON_TEST_TRUSTED") != 0) {
        qWarning() << "[ShellIpcServer] !!! MARATHON_TEST_TRUSTED is set -- IPC caller "
                      "verification is bypassed. Do NOT use in production.";
    }
    if (!bus.registerService("org.marathonos.Shell")) {

        qWarning() << "[ShellIpcServer] Failed to register service org.marathonos.Shell:"
                   << bus.lastError().message();
        return false;
    }

    auto *permObj     = new PermissionsObject(m_permissions, m_appLaunchService, this);
    auto *telephonyObj = new TelephonyObject(m_telephony, m_permissions, m_appLaunchService,
                                             m_audioRoutingManager, this);
    auto *settingsObj =
        new SettingsObject(m_settingsManager, m_permissions, m_appLaunchService, this);
    auto *securityObj =
        new SecurityObject(m_securityManager, m_permissions, m_appLaunchService, this);
    auto *btObj = new BluetoothObject(m_bluetoothManager, m_permissions, m_appLaunchService, this);
    auto *displayObj = new DisplayObject(m_display, m_rotationManager, m_flashlightManager,
                                       m_permissions, m_appLaunchService, this);
    auto *powerObj =
        new PowerObject(m_powerManager, m_display, m_permissions, m_appLaunchService, this);
    auto *audioObj =
        new AudioObject(m_audioManager, m_audioPolicy, m_permissions, m_appLaunchService, this);
    auto *networkObj = new NetworkObject(m_networkManager, m_permissions, m_appLaunchService, this);
    auto *navObj     = new NavigationObject(m_appLaunchService, this);
    if (m_foregroundApp)
        navObj->setForegroundApp(m_foregroundApp);
    navObj->setSessionStore(m_sessionStore);
    auto *hapticObj  = new HapticObject(m_hapticManager, m_appLaunchService, this);
    auto *sensorObj  = new SensorObject(m_display, m_permissions, m_appLaunchService, this);
    auto *locObj   = new LocationObject(m_locationManager, m_permissions, m_appLaunchService, this);
    auto *alarmObj = new AlarmObject(m_alarmManager, m_permissions, m_appLaunchService, this);
    auto *updatesObj = new UpdatesObject(m_updateService, m_permissions, m_appLaunchService, this);
    auto *appStoreObj =
        new AppStoreObject(m_appInstaller, m_permissions, m_appLaunchService, this);
    auto *lifecycleObj =
        new AppLifecycleObject(m_lifecycleManager, m_appRegistry, m_appLaunchService, this);

    bool ok = true;
    ok &= bus.registerObject("/org/marathonos/Shell/Permissions", permObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Telephony", telephonyObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Settings", settingsObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Security", securityObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Bluetooth", btObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Display", displayObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Power", powerObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Audio", audioObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Network", networkObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Navigation", navObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Haptic", hapticObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Sensor", sensorObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Location", locObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Alarm", alarmObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Updates", updatesObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/AppStore", appStoreObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/AppLifecycle", lifecycleObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    if (m_wallpaperStore)
        ok &= bus.registerObject("/org/marathonos/Shell/Wallpaper",
                                 new WallpaperObject(m_wallpaperStore, this),
                                 QDBusConnection::ExportAllSlots);
    if (m_modemManager)
        ok &= bus.registerObject(
            "/org/marathonos/Shell/Modem",
            new ModemObject(m_modemManager, m_permissions, m_appLaunchService, this),
            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    if (m_ambience)
        ok &= bus.registerObject("/org/marathonos/Shell/Ambience",
                                 new AmbienceObject(m_ambience, this),
                                 QDBusConnection::ExportAllSlots |
                                     QDBusConnection::ExportAllSignals);

    if (!ok) {
        qWarning() << "[ShellIpcServer] Failed to register one or more DBus objects:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[ShellIpcServer] DBus API registered (org.marathonos.Shell)";
    return true;
}
