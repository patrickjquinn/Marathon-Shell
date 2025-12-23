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

/**
 * Registers the shell-side DBus API used by isolated Marathon app processes.
 *
 * Service: org.marathonos.Shell
 * Objects:
 *  - /org/marathonos/Shell/Permissions   (org.marathonos.Shell.Permissions1)
 *  - /org/marathonos/Shell/Contacts     (org.marathonos.Shell.Contacts1)
 *  - /org/marathonos/Shell/CallHistory  (org.marathonos.Shell.CallHistory1)
 *  - /org/marathonos/Shell/Telephony    (org.marathonos.Shell.Telephony1)
 *  - /org/marathonos/Shell/Sms          (org.marathonos.Shell.Sms1)
 *  - /org/marathonos/Shell/MediaLibrary (org.marathonos.Shell.MediaLibrary1)
 *  - /org/marathonos/Shell/Settings     (org.marathonos.Shell.Settings1)
 *  - /org/marathonos/Shell/Bluetooth    (org.marathonos.Shell.Bluetooth1)
 *  - /org/marathonos/Shell/Display      (org.marathonos.Shell.Display1)
 *  - /org/marathonos/Shell/Power        (org.marathonos.Shell.Power1)
 *  - /org/marathonos/Shell/Audio        (org.marathonos.Shell.Audio1)
 *  - /org/marathonos/Shell/Network      (org.marathonos.Shell.Network1)
 */
class ShellIpcServer : public QObject {
    Q_OBJECT

  public:
    explicit ShellIpcServer(MarathonPermissionManager *permissions, ContactsManager *contacts,
                            CallHistoryManager *callHistory, TelephonyService *telephony,
                            SMSService *sms, MediaLibraryManager *mediaLibrary,
                            SettingsManager *settingsManager, BluetoothManager *bluetoothManager,
                            DisplayManagerCpp *displayManager, PowerManagerCpp *powerManager,
                            AudioManagerCpp *audioManager, AudioPolicyController *audioPolicy,
                            NetworkManagerCpp *networkManager, AppLaunchService *appLaunchService,
                            QObject *parent = nullptr);

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
    AppLaunchService          *m_appLaunchService = nullptr;
};
