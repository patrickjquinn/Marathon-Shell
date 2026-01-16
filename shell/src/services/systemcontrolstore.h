#pragma once

#include <QObject>
#include <QString>
#include <qqml.h>

class NetworkManagerCpp;
class BluetoothManager;
class DisplayManagerCpp;
class FlashlightManagerCpp;
class ModemManagerCpp;
class SettingsManager;
class AlarmManagerCpp;
class LocationManager;
class HapticManager;
class PowerManagerCpp;
class AudioManagerCpp;
class AudioPolicyController;
class ScreenshotServiceCpp;

class SystemControlStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool isWifiOn READ isWifiOn NOTIFY isWifiOnChanged)
    Q_PROPERTY(bool isBluetoothOn READ isBluetoothOn NOTIFY isBluetoothOnChanged)
    Q_PROPERTY(bool isAirplaneModeOn READ isAirplaneModeOn NOTIFY isAirplaneModeOnChanged)
    Q_PROPERTY(bool isRotationLocked READ isRotationLocked NOTIFY isRotationLockedChanged)
    Q_PROPERTY(bool isFlashlightOn READ isFlashlightOn NOTIFY isFlashlightOnChanged)
    Q_PROPERTY(bool isCellularOn READ isCellularOn NOTIFY isCellularOnChanged)
    Q_PROPERTY(bool isCellularDataOn READ isCellularDataOn NOTIFY isCellularDataOnChanged)
    Q_PROPERTY(bool isDndMode READ isDndMode NOTIFY isDndModeChanged)
    Q_PROPERTY(bool isAlarmOn READ isAlarmOn NOTIFY isAlarmOnChanged)
    Q_PROPERTY(bool isAutoBrightnessOn READ isAutoBrightnessOn NOTIFY isAutoBrightnessOnChanged)
    Q_PROPERTY(bool isLocationOn READ isLocationOn NOTIFY isLocationOnChanged)
    Q_PROPERTY(bool isHotspotOn READ isHotspotOn NOTIFY isHotspotOnChanged)
    Q_PROPERTY(bool isVibrationOn READ isVibrationOn NOTIFY isVibrationOnChanged)
    Q_PROPERTY(bool isNightLightOn READ isNightLightOn NOTIFY isNightLightOnChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool isLowPowerMode READ isLowPowerMode NOTIFY isLowPowerModeChanged)

  public:
    explicit SystemControlStore(NetworkManagerCpp    *networkManager,
                                BluetoothManager     *bluetoothManager,
                                DisplayManagerCpp    *displayManager,
                                FlashlightManagerCpp *flashlightManager,
                                ModemManagerCpp *modemManager, SettingsManager *settingsManager,
                                AlarmManagerCpp *alarmManager, LocationManager *locationManager,
                                HapticManager *hapticManager, PowerManagerCpp *powerManager,
                                AudioManagerCpp       *audioManager,
                                AudioPolicyController *audioPolicyController,
                                ScreenshotServiceCpp *screenshotService, QObject *parent = nullptr);

    bool isWifiOn() const {
        return m_isWifiOn;
    }
    bool isBluetoothOn() const {
        return m_isBluetoothOn;
    }
    bool isAirplaneModeOn() const {
        return m_isAirplaneModeOn;
    }
    bool isRotationLocked() const {
        return m_isRotationLocked;
    }
    bool isFlashlightOn() const {
        return m_isFlashlightOn;
    }
    bool isCellularOn() const {
        return m_isCellularOn;
    }
    bool isCellularDataOn() const {
        return m_isCellularDataOn;
    }
    bool isDndMode() const {
        return m_isDndMode;
    }
    bool isAlarmOn() const {
        return m_isAlarmOn;
    }
    bool isAutoBrightnessOn() const {
        return m_isAutoBrightnessOn;
    }
    bool isLocationOn() const {
        return m_isLocationOn;
    }
    bool isHotspotOn() const {
        return m_isHotspotOn;
    }
    bool isVibrationOn() const {
        return m_isVibrationOn;
    }
    bool isNightLightOn() const {
        return m_isNightLightOn;
    }
    int brightness() const {
        return m_brightness;
    }
    int volume() const {
        return m_volume;
    }
    bool isLowPowerMode() const {
        return m_isLowPowerMode;
    }

    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void toggleBluetooth();
    Q_INVOKABLE void toggleAirplaneMode();
    Q_INVOKABLE void toggleRotationLock();
    Q_INVOKABLE void toggleFlashlight();
    Q_INVOKABLE void toggleCellular();
    Q_INVOKABLE void toggleCellularData();
    Q_INVOKABLE void toggleDndMode();
    Q_INVOKABLE void toggleAlarm();
    Q_INVOKABLE void toggleLowPowerMode();
    Q_INVOKABLE void toggleAutoBrightness();
    Q_INVOKABLE void toggleLocation();
    Q_INVOKABLE void toggleHotspot();
    Q_INVOKABLE void toggleVibration();
    Q_INVOKABLE void toggleNightLight();
    Q_INVOKABLE void captureScreenshot();
    Q_INVOKABLE void setBrightness(int value);
    Q_INVOKABLE void setVolume(int value);
    Q_INVOKABLE void sleep();
    Q_INVOKABLE void powerOff();
    Q_INVOKABLE void reboot();

  signals:
    void isWifiOnChanged();
    void isBluetoothOnChanged();
    void isAirplaneModeOnChanged();
    void isRotationLockedChanged();
    void isFlashlightOnChanged();
    void isCellularOnChanged();
    void isCellularDataOnChanged();
    void isDndModeChanged();
    void isAlarmOnChanged();
    void isAutoBrightnessOnChanged();
    void isLocationOnChanged();
    void isHotspotOnChanged();
    void isVibrationOnChanged();
    void isNightLightOnChanged();
    void brightnessChanged();
    void volumeChanged();
    void isLowPowerModeChanged();

  private:
    void                   setIsWifiOn(bool enabled);
    void                   setIsBluetoothOn(bool enabled);
    void                   setIsAirplaneModeOn(bool enabled);
    void                   setIsRotationLocked(bool enabled);
    void                   setIsFlashlightOn(bool enabled);
    void                   setIsCellularOn(bool enabled);
    void                   setIsCellularDataOn(bool enabled);
    void                   setIsDndMode(bool enabled);
    void                   setIsAlarmOn(bool enabled);
    void                   setIsAutoBrightnessOn(bool enabled);
    void                   setIsLocationOn(bool enabled);
    void                   setIsHotspotOn(bool enabled);
    void                   setIsVibrationOn(bool enabled);
    void                   setIsNightLightOn(bool enabled);
    void                   setBrightnessValue(int value);
    void                   setVolumeValue(int value);
    void                   setIsLowPowerMode(bool enabled);
    void                   refreshAlarmState();

    NetworkManagerCpp     *m_networkManager;
    BluetoothManager      *m_bluetoothManager;
    DisplayManagerCpp     *m_displayManager;
    FlashlightManagerCpp  *m_flashlightManager;
    ModemManagerCpp       *m_modemManager;
    SettingsManager       *m_settingsManager;
    AlarmManagerCpp       *m_alarmManager;
    LocationManager       *m_locationManager;
    HapticManager         *m_hapticManager;
    PowerManagerCpp       *m_powerManager;
    AudioManagerCpp       *m_audioManager;
    AudioPolicyController *m_audioPolicyController;
    ScreenshotServiceCpp  *m_screenshotService;

    bool                   m_isWifiOn           = true;
    bool                   m_isBluetoothOn      = false;
    bool                   m_isAirplaneModeOn   = false;
    bool                   m_isRotationLocked   = false;
    bool                   m_isFlashlightOn     = false;
    bool                   m_isCellularOn       = false;
    bool                   m_isCellularDataOn   = false;
    bool                   m_isDndMode          = false;
    bool                   m_isAlarmOn          = false;
    bool                   m_isAutoBrightnessOn = false;
    bool                   m_isLocationOn       = false;
    bool                   m_isHotspotOn        = false;
    bool                   m_isVibrationOn      = true;
    bool                   m_isNightLightOn     = false;
    int                    m_brightness         = 50;
    int                    m_volume             = 50;
    bool                   m_isLowPowerMode     = false;
};
