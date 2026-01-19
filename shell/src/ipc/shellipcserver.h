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
class AudioManagerCpp;
class AudioPolicyController;
class HapticManager;
class SecurityManager;
class SensorManagerCpp;
class LocationManager;
class AlarmManagerCpp;

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
                            AppLaunchService *appLaunchService, QObject *parent = nullptr);

    bool registerOnSessionBus();

  private:
    MarathonPermissionManager *m_permissions      = nullptr;
    ContactsManager           *m_contacts         = nullptr;
    CallHistoryManager        *m_callHistory      = nullptr;
    TelephonyService          *m_telephony        = nullptr;
    SMSService                *m_sms              = nullptr;
    MediaLibraryManager       *m_mediaLibrary     = nullptr;
    SettingsManager           *m_settingsManager  = nullptr;
    BluetoothManager          *m_bluetoothManager = nullptr;
    DisplayManagerCpp         *m_displayManager   = nullptr;
    PowerManagerCpp           *m_powerManager     = nullptr;
    AudioManagerCpp           *m_audioManager     = nullptr;
    AudioPolicyController     *m_audioPolicy      = nullptr;
    NetworkManagerCpp         *m_networkManager   = nullptr;
    HapticManager             *m_hapticManager    = nullptr;
    SecurityManager           *m_securityManager  = nullptr;
    SensorManagerCpp          *m_sensorManager    = nullptr;
    LocationManager           *m_locationManager  = nullptr;
    AlarmManagerCpp           *m_alarmManager     = nullptr;
    AppLaunchService          *m_appLaunchService = nullptr;
};
