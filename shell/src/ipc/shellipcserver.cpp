#include "shellipcserver.h"

#include "shellservices.h"

#include "marathonpermissionmanager.h"

#include "callhistorymanager.h"
#include "contactsmanager.h"
#include "smsservice.h"
#include "telephonyservice.h"
#include "medialibrarymanager.h"
#include "settingsmanager.h"
#include "bluetoothmanager.h"
#include "displaymanagercpp.h"
#include "networkmanagercpp.h"
#include "powermanagercpp.h"
#include "audiomanagercpp.h"
#include "audiopolicycontroller.h"
#include "hapticmanager.h"
#include "sensormanagercpp.h"
#include "locationmanager.h"
#include "alarmmanagercpp.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

ShellIpcServer::ShellIpcServer(MarathonPermissionManager *permissions, ContactsManager *contacts,
                               CallHistoryManager *callHistory, TelephonyService *telephony,
                               SMSService *sms, MediaLibraryManager *mediaLibrary,
                               SettingsManager *settingsManager, BluetoothManager *bluetoothManager,
                               DisplayManagerCpp *displayManager, PowerManagerCpp *powerManager,
                               AudioManagerCpp *audioManager, AudioPolicyController *audioPolicy,
                               NetworkManagerCpp *networkManager, HapticManager *hapticManager,
                               SecurityManager *securityManager, SensorManagerCpp *sensorManager,
                               LocationManager *locationManager, AlarmManagerCpp *alarmManager,
                               AppLaunchService *appLaunchService, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_contacts(contacts)
    , m_callHistory(callHistory)
    , m_telephony(telephony)
    , m_sms(sms)
    , m_mediaLibrary(mediaLibrary)
    , m_settingsManager(settingsManager)
    , m_bluetoothManager(bluetoothManager)
    , m_displayManager(displayManager)
    , m_powerManager(powerManager)
    , m_audioManager(audioManager)
    , m_audioPolicy(audioPolicy)
    , m_networkManager(networkManager)
    , m_hapticManager(hapticManager)
    , m_securityManager(securityManager)
    , m_sensorManager(sensorManager)
    , m_locationManager(locationManager)
    , m_alarmManager(alarmManager)
    , m_appLaunchService(appLaunchService) {}

bool ShellIpcServer::registerOnSessionBus() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[ShellIpcServer] Session bus not connected:" << bus.lastError().message();
        return false;
    }

    qInfo() << "[ShellIpcServer] Registering DBus service org.marathonos.Shell…";
    if (!bus.registerService("org.marathonos.Shell")) {

        qWarning() << "[ShellIpcServer] Failed to register service org.marathonos.Shell:"
                   << bus.lastError().message();
        return false;
    }

    auto *permObj     = new PermissionsObject(m_permissions, m_appLaunchService, this);
    auto *contactsObj = new ContactsObject(m_contacts, m_permissions, m_appLaunchService, this);
    auto *callHistoryObj =
        new CallHistoryObject(m_callHistory, m_permissions, m_appLaunchService, this);
    auto *telephonyObj = new TelephonyObject(m_telephony, m_permissions, m_appLaunchService, this);
    auto *smsObj       = new SmsObject(m_sms, m_permissions, m_appLaunchService, this);
    auto *mediaObj =
        new MediaLibraryObject(m_mediaLibrary, m_permissions, m_appLaunchService, this);
    auto *settingsObj =
        new SettingsObject(m_settingsManager, m_permissions, m_appLaunchService, this);
    auto *securityObj =
        new SecurityObject(m_securityManager, m_permissions, m_appLaunchService, this);
    auto *btObj = new BluetoothObject(m_bluetoothManager, m_permissions, m_appLaunchService, this);
    auto *displayObj = new DisplayObject(m_displayManager, m_permissions, m_appLaunchService, this);
    auto *powerObj   = new PowerObject(m_powerManager, m_permissions, m_appLaunchService, this);
    auto *audioObj =
        new AudioObject(m_audioManager, m_audioPolicy, m_permissions, m_appLaunchService, this);
    auto *networkObj = new NetworkObject(m_networkManager, m_permissions, m_appLaunchService, this);
    auto *navObj     = new NavigationObject(m_appLaunchService, this);
    auto *hapticObj  = new HapticObject(m_hapticManager, m_appLaunchService, this);
    auto *sensorObj  = new SensorObject(m_sensorManager, m_appLaunchService, this);
    auto *locObj     = new LocationObject(m_locationManager, m_appLaunchService, this);
    auto *alarmObj   = new AlarmObject(m_alarmManager, m_appLaunchService, this);

    bool  ok = true;
    ok &= bus.registerObject("/org/marathonos/Shell/Permissions", permObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Contacts", contactsObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/CallHistory", callHistoryObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Telephony", telephonyObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/Sms", smsObj,
                             QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    ok &= bus.registerObject("/org/marathonos/Shell/MediaLibrary", mediaObj,
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

    if (!ok) {
        qWarning() << "[ShellIpcServer] Failed to register one or more DBus objects:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[ShellIpcServer] DBus API registered (org.marathonos.Shell)";
    return true;
}
